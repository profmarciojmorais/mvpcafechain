// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockV3Aggregator
 * @notice Simula o Chainlink AggregatorV3Interface para testes no Remix/localhost.
 *         Em produção (Sepolia) substituir pelo endereço real:
 *         ETH/USD Sepolia: 0x694AA1769357215DE4FAC081bf1f309aDC325306
 */
contract MockV3Aggregator {
    uint8   public decimals;
    int256  public latestAnswer;
    uint256 public updatedAt;
    uint80  private _roundId;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals     = _decimals;
        latestAnswer = _initialAnswer;
        updatedAt    = block.timestamp;
        _roundId     = 1;
    }

    /**
     * @notice Atualiza o preço simulado. Use para testar diferentes APRs.
     * @param _answer Novo preço (ex: 2500 * 10**8 = $2.500)
     */
    function updateAnswer(int256 _answer) external {
        latestAnswer = _answer;
        updatedAt    = block.timestamp;
        _roundId++;
    }

    function latestRoundData()
        external view
        returns (
            uint80  roundId,
            int256  answer,
            uint256 startedAt,
            uint256 updatedAt_,
            uint80  answeredInRound
        )
    {
        return (_roundId, latestAnswer, updatedAt, updatedAt, _roundId);
    }
}
