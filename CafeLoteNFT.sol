// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title CafeLoteNFT
 * @notice NFT ERC-721 que representa um lote rastreável de café.
 *         Cada token = 1 lote físico com metadados de origem, qualidade e exportação.
 * @dev Metadados armazenados on-chain (struct) + URI IPFS para certificados.
 */
contract CafeLoteNFT is ERC721, ERC721URIStorage, ERC721Burnable, AccessControl {
    using Counters for Counters.Counter;

    bytes32 public constant MINTER_ROLE   = keccak256("MINTER_ROLE");
    bytes32 public constant AUDITOR_ROLE  = keccak256("AUDITOR_ROLE");

    Counters.Counter private _tokenIdCounter;

    // ── Enums ────────────────────────────────────────────────────────────────
    enum StatusLote {
        PRODUCAO,      // Em fazenda
        BENEFICIAMENTO,
        ARMAZENADO,
        EXPORTADO,
        ENTREGUE
    }

    enum ClassificacaoCafe {
        ESPECIAL,      // Score SCA ≥ 80
        FINOS,         // 75-79
        COMERCIAL,     // < 75
        ORGANICO
    }

    // ── Structs ───────────────────────────────────────────────────────────────
    struct LoteCafe {
        string  fazenda;           // Nome da fazenda de origem
        string  municipio;         // Município de origem
        string  estado;            // UF (ex: "MG", "SP", "ES")
        uint256 sacasProduzidas;   // Número de sacas de 60 kg
        uint256 dataColheita;      // Unix timestamp
        uint256 scoreSCA;          // Score de qualidade (0-100, sem decimais)
        ClassificacaoCafe classificacao;
        StatusLote        status;
        bool    exportado;
        string  paisDestino;       // Destino da exportação
        uint256 precoUSDPorSaca;   // Preço em USD (x100 para 2 casas decimais)
    }

    //   Struct de input para evitar "stack too deep" na mintLote
    struct MintLoteParams {
        address to;
        string fazenda;
        string municipio;
        string estado;
        uint256 sacas;
        uint256 dataColheita;
        uint256 scoreSCA;
        ClassificacaoCafe classificacao;
        string uri;
    }

    // ── Storage ──────────────────────────────────────────────────────────────
    mapping(uint256 => LoteCafe) public lotes;

    // ── Events ───────────────────────────────────────────────────────────────
    event LoteMinted(uint256 indexed tokenId, address indexed produtor, string fazenda, uint256 sacas);
    event StatusAtualizado(uint256 indexed tokenId, StatusLote novoStatus);
    event LoteExportado(uint256 indexed tokenId, string paisDestino, uint256 precoUSD);

    // ── Constructor ──────────────────────────────────────────────────────────
    constructor(address admin) ERC721("CafeLoteNFT", "CAFELOTE") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(AUDITOR_ROLE, admin);
    }

    // ── Mint ─────────────────────────────────────────────────────────────────
    /**
     * @notice Cunha NFT de lote de café para um produtor.
     * @param p  Struct MintLoteParams com todos os dados do lote.
     */
    function mintLote(MintLoteParams calldata p)  //  parâmetros agrupados em struct
        external
        onlyRole(MINTER_ROLE)
        returns (uint256)
    {
        require(p.sacas > 0, "CafeLoteNFT: sacas deve ser > 0");
        require(p.scoreSCA <= 100, "CafeLoteNFT: score invalido");

        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();

        _safeMint(p.to, tokenId);
        _setTokenURI(tokenId, p.uri);

        lotes[tokenId] = LoteCafe({
            fazenda:          p.fazenda,
            municipio:        p.municipio,
            estado:           p.estado,
            sacasProduzidas:  p.sacas,
            dataColheita:     p.dataColheita,
            scoreSCA:         p.scoreSCA,
            classificacao:    p.classificacao,
            status:           StatusLote.PRODUCAO,
            exportado:        false,
            paisDestino:      "",
            precoUSDPorSaca:  0
        });

        emit LoteMinted(tokenId, p.to, p.fazenda, p.sacas);
        return tokenId;
    }

    // ── Status ────────────────────────────────────────────────────────────────
    /**
     * @notice Auditor atualiza status do lote na cadeia produtiva.
     */
    function atualizarStatus(uint256 tokenId, StatusLote novoStatus)
        external
        onlyRole(AUDITOR_ROLE)
    {
        require(_ownerOf(tokenId) != address(0), "CafeLoteNFT: token inexistente");
        lotes[tokenId].status = novoStatus;
        emit StatusAtualizado(tokenId, novoStatus);
    }

    /**
     * @notice Registra exportacao do lote.
     * @param precoUSD Preco em USD x100 (ex: 24050 = $240,50/saca)
     */
    function registrarExportacao(uint256 tokenId, string calldata pais, uint256 precoUSD)
        external
        onlyRole(AUDITOR_ROLE)
    {
        require(_ownerOf(tokenId) != address(0), "CafeLoteNFT: token inexistente");
        LoteCafe storage lote = lotes[tokenId];
        lote.exportado       = true;
        lote.paisDestino     = pais;
        lote.precoUSDPorSaca = precoUSD;
        lote.status          = StatusLote.EXPORTADO;
        emit LoteExportado(tokenId, pais, precoUSD);
    }

    // ── Getters ───────────────────────────────────────────────────────────────
    function getLote(uint256 tokenId) external view returns (LoteCafe memory) {
        require(_ownerOf(tokenId) != address(0), "CafeLoteNFT: token inexistente");
        return lotes[tokenId];
    }

    function totalLotes() external view returns (uint256) {
        return _tokenIdCounter.current();
    }

    // ── Overrides necessários ─────────────────────────────────────────────────
    function tokenURI(uint256 tokenId)
        public view override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
} //  CORREÇÃO: fechamento correto do contrato
