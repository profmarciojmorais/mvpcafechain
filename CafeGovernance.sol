// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title CafeGovernance  –  DAO Simplificada
 * @notice Governança on-chain do protocolo CafeChain.
 *
 * ─── FLUXO ───────────────────────────────────────────────────────────────────
 *  1. Qualquer holder de CFT (≥ quorumMin) pode criar proposta.
 *  2. Período de votação: VOTING_PERIOD segundos.
 *  3. Voto ponderado pelo saldo CFT no momento da votação.
 *  4. Aprovação: votos SIM > votos NÃO e total de votos ≥ quorum global.
 *  5. Após aprovação, owner executa a proposta (off-chain ou chamada de contrato).
 * ─────────────────────────────────────────────────────────────────────────────
 */
contract CafeGovernance is ReentrancyGuard, Ownable {

    // ── Constantes ────────────────────────────────────────────────────────────
    uint256 public constant VOTING_PERIOD   = 7 days;
    uint256 public constant MIN_TOKENS_PROPOSE = 1_000 * 10**18; // 1.000 CFT

    // ── State ─────────────────────────────────────────────────────────────────
    IERC20  public immutable cafeToken;
    uint256 public quorum;          // Mínimo de votos (em CFT wei) para proposta ser válida
    uint256 public proposalCount;

    enum ProposalStatus { ATIVA, APROVADA, REJEITADA, EXECUTADA }

    struct Proposal {
        uint256 id;
        address proposer;
        string  titulo;
        string  descricao;
        uint256 votosA_Favor;   // Soma de CFT votados SIM
        uint256 votosContra;    // Soma de CFT votados NÃO
        uint256 inicio;         // Timestamp de criação
        uint256 fim;            // Timestamp de encerramento
        ProposalStatus status;
        address targetContract; // Contrato alvo (0x0 = proposta off-chain)
        bytes   callData;       // Dados da chamada (se on-chain)
    }

    mapping(uint256 => Proposal)           public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    // ── Events ────────────────────────────────────────────────────────────────
    event PropostaCriada(uint256 indexed id, address indexed proposer, string titulo);
    event VotoRegistrado(uint256 indexed proposalId, address indexed voter, bool apoio, uint256 peso);
    event PropostaFinalizada(uint256 indexed id, ProposalStatus status);
    event PropostaExecutada(uint256 indexed id);

    // ── Constructor ───────────────────────────────────────────────────────────
    /**
     * @param _cafeToken Endereço do CFT
     * @param _quorum    Quórum mínimo em CFT (ex: 10_000 * 1e18)
     */
    constructor(address _cafeToken, uint256 _quorum) Ownable(msg.sender) {
        require(_cafeToken != address(0), "Gov: token zero");
        cafeToken = IERC20(_cafeToken);
        quorum    = _quorum;
    }

    // ── Proposta ──────────────────────────────────────────────────────────────
    /**
     * @notice Cria nova proposta. Requer saldo ≥ MIN_TOKENS_PROPOSE.
     * @param titulo         Título curto da proposta
     * @param descricao      Descrição detalhada
     * @param targetContract Endereço do contrato alvo (0x0 para off-chain)
     * @param data           calldata da execução (vazio para off-chain)
     */
    function criarProposta(
        string calldata titulo,
        string calldata descricao,
        address targetContract,
        bytes calldata data
    ) external returns (uint256) {
        require(
            cafeToken.balanceOf(msg.sender) >= MIN_TOKENS_PROPOSE,
            "Gov: saldo insuficiente para propor"
        );
        require(bytes(titulo).length > 0, "Gov: titulo vazio");

        proposalCount++;
        uint256 id = proposalCount;

        proposals[id] = Proposal({
            id:              id,
            proposer:        msg.sender,
            titulo:          titulo,
            descricao:       descricao,
            votosA_Favor:    0,
            votosContra:     0,
            inicio:          block.timestamp,
            fim:             block.timestamp + VOTING_PERIOD,
            status:          ProposalStatus.ATIVA,
            targetContract:  targetContract,
            callData:        data
        });

        emit PropostaCriada(id, msg.sender, titulo);
        return id;
    }

    // ── Votação ───────────────────────────────────────────────────────────────
    /**
     * @notice Vota em uma proposta. Peso = saldo CFT atual.
     * @param proposalId ID da proposta
     * @param apoio      true = SIM / false = NÃO
     */
    function votar(uint256 proposalId, bool apoio) external nonReentrant {
        Proposal storage p = proposals[proposalId];
        require(p.status == ProposalStatus.ATIVA,  "Gov: proposta nao ativa");
        require(block.timestamp <= p.fim,           "Gov: votacao encerrada");
        require(!hasVoted[proposalId][msg.sender],  "Gov: ja votou");

        uint256 peso = cafeToken.balanceOf(msg.sender);
        require(peso > 0, "Gov: sem tokens para votar");

        hasVoted[proposalId][msg.sender] = true;

        if (apoio) {
            p.votosA_Favor += peso;
        } else {
            p.votosContra += peso;
        }

        emit VotoRegistrado(proposalId, msg.sender, apoio, peso);
    }

    // ── Finalizar ─────────────────────────────────────────────────────────────
    /**
     * @notice Finaliza proposta após período de votação.
     *         Qualquer pessoa pode chamar após p.fim.
     */
    function finalizarProposta(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(p.status == ProposalStatus.ATIVA, "Gov: ja finalizada");
        require(block.timestamp > p.fim, "Gov: votacao ainda ativa");

        uint256 totalVotos = p.votosA_Favor + p.votosContra;

        if (totalVotos >= quorum && p.votosA_Favor > p.votosContra) {
            p.status = ProposalStatus.APROVADA;
        } else {
            p.status = ProposalStatus.REJEITADA;
        }

        emit PropostaFinalizada(proposalId, p.status);
    }

    // ── Execução (on-chain) ───────────────────────────────────────────────────
    /**
     * @notice Owner executa proposta aprovada com targetContract definido.
     */
    function executarProposta(uint256 proposalId) external onlyOwner nonReentrant {
        Proposal storage p = proposals[proposalId];
        require(p.status == ProposalStatus.APROVADA, "Gov: nao aprovada");
        require(p.targetContract != address(0),      "Gov: proposta off-chain");

        p.status = ProposalStatus.EXECUTADA;

        (bool success, ) = p.targetContract.call(p.callData);
        require(success, "Gov: execucao falhou");

        emit PropostaExecutada(proposalId);
    }

    // ── Admin ─────────────────────────────────────────────────────────────────
    function setQuorum(uint256 novoQuorum) external onlyOwner {
        quorum = novoQuorum;
    }

    // ── Views ─────────────────────────────────────────────────────────────────
    function getProposta(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    function tempoRestante(uint256 proposalId) external view returns (uint256) {
        Proposal storage p = proposals[proposalId];
        if (block.timestamp >= p.fim) return 0;
        return p.fim - block.timestamp;
    }
}
