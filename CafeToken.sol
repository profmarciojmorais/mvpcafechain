// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title CafeToken (CFT)
 * @notice Token ERC-20 nativo do protocolo CafeChain
 *         Representa créditos de produção e exportação de café.
 * @dev Utiliza OpenZeppelin ^5.x com AccessControl
 */
contract CafeToken is ERC20, ERC20Burnable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant MAX_SUPPLY = 100_000_000 * 10 ** 18; // 100 milhões CFT

    event TokensMinted(address indexed to, uint256 amount, string reason);

    constructor(address admin) ERC20("CafeToken", "CFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        // Mint inicial para o admin (treasury)
        _mint(admin, 10_000_000 * 10 ** 18);
    }

    /**
     * @notice Cunha novos tokens. Apenas MINTER_ROLE.
     * @param to Destinatário
     * @param amount Quantidade em wei
     * @param reason Justificativa (ex: "ProducaoSafra2025")
     */
    function mint(address to, uint256 amount, string calldata reason)
        external
        onlyRole(MINTER_ROLE)
    {
        require(totalSupply() + amount <= MAX_SUPPLY, "CafeToken: max supply excedido");
        _mint(to, amount);
        emit TokensMinted(to, amount, reason);
    }

    /**
     * @notice Retorna o número de casas decimais (padrão 18)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    // Suporte a interface
    function supportsInterface(bytes4 interfaceId)
        public view override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
