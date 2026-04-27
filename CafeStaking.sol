// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Interface Chainlink AggregatorV3
interface AggregatorV3Interface {
    function latestRoundData()
        external view
        returns (
            uint80  roundId,
            int256  answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80  answeredInRound
        );
    function decimals() external view returns (uint8);
}

/**
 * @title CafeStaking
 * @notice Staking de CFT com recompensa dinâmica baseada no preço do café
 *         (simulado via preço ETH/USD Chainlink na testnet Sepolia).
 *
 * ─── LÓGICA DE RECOMPENSA ────────────────────────────────────────────────────
 *  APR base = 12% ao ano
 *  Bônus de preço:
 *    - Preço ETH > $2.000 USD → +3% bonus (proxy de mercado "em alta")
 *    - Preço ETH > $3.000 USD → +6% bonus
 *  Recompensa por segundo = (staked * APR_total) / (365 days * 100)
 * ─────────────────────────────────────────────────────────────────────────────
 */
contract CafeStaking is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ── State ─────────────────────────────────────────────────────────────────
    IERC20  public immutable cafeToken;
    AggregatorV3Interface public priceFeed; // ETH/USD Chainlink Sepolia

    uint256 public constant BASE_APR        = 12;   // 12% ao ano
    uint256 public constant BONUS_APR_MID   = 3;    // +3% se preço > threshold1
    uint256 public constant BONUS_APR_HIGH  = 6;    // +6% se preço > threshold2
    int256  public constant PRICE_THRESHOLD_MID  = 2000 * 10**8; // $2.000 (8 dec Chainlink)
    int256  public constant PRICE_THRESHOLD_HIGH = 3000 * 10**8; // $3.000

    uint256 public totalStaked;
    uint256 public rewardPool;        // Tokens depositados pelo owner para pagar rewards

    struct StakeInfo {
        uint256 amount;
        uint256 since;       // timestamp do stake
        uint256 rewardDebt;  // rewards já sacados
    }

    mapping(address => StakeInfo) public stakes;

    // ── Events ────────────────────────────────────────────────────────────────
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount, uint256 reward);
    event RewardClaimed(address indexed user, uint256 reward);
    event RewardPoolFunded(uint256 amount);
    event PriceFeedUpdated(address newFeed);

    // ── Constructor ───────────────────────────────────────────────────────────
    /**
     * @param _cafeToken  Endereço do CFT
     * @param _priceFeed  Chainlink ETH/USD Sepolia: 0x694AA1769357215DE4FAC081bf1f309aDC325306
     */
    constructor(address _cafeToken, address _priceFeed) Ownable(msg.sender) {
        require(_cafeToken != address(0), "Staking: token zero address");
        cafeToken  = IERC20(_cafeToken);
        priceFeed  = AggregatorV3Interface(_priceFeed);
    }

    // ── Owner: abastecer pool de recompensa ──────────────────────────────────
    function fundRewardPool(uint256 amount) external onlyOwner {
        cafeToken.safeTransferFrom(msg.sender, address(this), amount);
        rewardPool += amount;
        emit RewardPoolFunded(amount);
    }

    function updatePriceFeed(address newFeed) external onlyOwner {
        priceFeed = AggregatorV3Interface(newFeed);
        emit PriceFeedUpdated(newFeed);
    }

    // ── Oráculo ───────────────────────────────────────────────────────────────
    /**
     * @notice Lê preço ETH/USD do Chainlink.
     * @return price  Preço com 8 casas decimais (padrão Chainlink).
     */
    function getLatestPrice() public view returns (int256 price) {
        (, price,,,) = priceFeed.latestRoundData();
    }

    /**
     * @notice Calcula APR efetivo baseado no preço atual.
     */
    function getEffectiveAPR() public view returns (uint256 apr) {
        int256 price = getLatestPrice();
        apr = BASE_APR;
        if (price >= PRICE_THRESHOLD_HIGH) {
            apr += BONUS_APR_HIGH;
        } else if (price >= PRICE_THRESHOLD_MID) {
            apr += BONUS_APR_MID;
        }
    }

    // ── Staking ───────────────────────────────────────────────────────────────
    /**
     * @notice Deposita CFT em staking.
     * @param amount Quantidade em wei
     */
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Staking: amount zero");

        StakeInfo storage info = stakes[msg.sender];

        // Se já tem stake ativo, coleta reward pendente antes de adicionar
        if (info.amount > 0) {
            uint256 pending = _calcReward(msg.sender);
            info.rewardDebt += pending;
        }

        cafeToken.safeTransferFrom(msg.sender, address(this), amount);
        info.amount += amount;
        info.since   = block.timestamp;
        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Retira CFT do staking + coleta recompensas.
     * @param amount Quantidade a retirar (0 = apenas coletar reward)
     */
    function unstake(uint256 amount) external nonReentrant {
        StakeInfo storage info = stakes[msg.sender];
        require(info.amount >= amount, "Staking: saldo insuficiente");

        uint256 reward = _calcReward(msg.sender) + info.rewardDebt;
        info.rewardDebt = 0;
        info.since      = block.timestamp;

        if (amount > 0) {
            info.amount -= amount;
            totalStaked -= amount;
            cafeToken.safeTransfer(msg.sender, amount);
        }

        if (reward > 0 && rewardPool >= reward) {
            rewardPool -= reward;
            cafeToken.safeTransfer(msg.sender, reward);
        }

        emit Unstaked(msg.sender, amount, reward);
    }

    /**
     * @notice Coleta apenas a recompensa sem retirar o principal.
     */
    function claimReward() external nonReentrant {
        StakeInfo storage info = stakes[msg.sender];
        uint256 reward = _calcReward(msg.sender) + info.rewardDebt;
        require(reward > 0, "Staking: sem recompensa");
        require(rewardPool >= reward, "Staking: pool insuficiente");

        info.rewardDebt = 0;
        info.since      = block.timestamp;
        rewardPool     -= reward;

        cafeToken.safeTransfer(msg.sender, reward);
        emit RewardClaimed(msg.sender, reward);
    }

    // ── Views ─────────────────────────────────────────────────────────────────
    /**
     * @notice Retorna recompensa acumulada pendente de um usuário.
     */
    function pendingReward(address user) external view returns (uint256) {
        StakeInfo storage info = stakes[user];
        return _calcReward(user) + info.rewardDebt;
    }

    // ── Internal ──────────────────────────────────────────────────────────────
    function _calcReward(address user) internal view returns (uint256) {
        StakeInfo storage info = stakes[user];
        if (info.amount == 0) return 0;

        uint256 elapsed = block.timestamp - info.since;
        uint256 apr     = getEffectiveAPR();

        // reward = (amount * apr * elapsed) / (365 days * 100)
        return (info.amount * apr * elapsed) / (365 days * 100);
    }
}
