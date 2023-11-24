// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./BansheesRaffle.sol";

contract BansheeRaffleAutomation is
    VRFConsumerBaseV2,
    AutomationCompatibleInterface,
    AccessControl
{
    event WinnerPicked(address indexed player);

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    BansheesRaffle public bansheesRaffle;
    VRFCoordinatorV2Interface COORDINATOR;

    uint64 s_subscriptionId;

    bytes32 keyHash =
        0xd729dc84e21ae57ffb6be0053bf2b0668aa2aaf300a2a7b2ddf7dc0bb6e875a8;

    uint32 callbackGasLimit = 2_000_000;

    uint16 requestConfirmations = 3;

    uint32 numWords = 1;
    struct RaffleStatus {
        uint256 randomWord;
        bool fulfilled;
        address winner;
        uint256 raffleId;
    }

    mapping(uint256 => RaffleStatus) public statuses;

    constructor(uint64 subscriptionId, address _raffleContract)
        VRFConsumerBaseV2(0xAE975071Be8F8eE67addBC1A82488F1C24858067)
    {
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        COORDINATOR = VRFCoordinatorV2Interface(
            0xAE975071Be8F8eE67addBC1A82488F1C24858067
        );
        s_subscriptionId = subscriptionId;
        bansheesRaffle = BansheesRaffle(_raffleContract);
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        (uint256 rafflesCount, , ) = bansheesRaffle.getRafflesInfo(0);
        for (uint256 i = 0; i < rafflesCount; i++) {
            if (isUpkeepNeeded(i)) {
                upkeepNeeded = true;
                return (upkeepNeeded, abi.encode(i));
            }
        }
        upkeepNeeded = false;
        return (upkeepNeeded, performData);
    }

    function isUpkeepNeeded(uint256 raffleId) internal view returns (bool) {
        (
            ,
            uint256 endDate,
            BansheesRaffle.RaffleState raffleState
        ) = bansheesRaffle.getRafflesInfo(raffleId);

        return
            endDate <= block.timestamp &&
            raffleState == BansheesRaffle.RaffleState.Open;
    }

    function performUpkeep(bytes calldata performData) external override {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not admin");

        uint256 raffleId = abi.decode(performData, (uint256));
        pickWinner(raffleId);
    }

    function pickWinner(uint256 _raffleId) internal returns (uint256) {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not admin");
        (uint256 rafflesCount, , ) = bansheesRaffle.getRafflesInfo(0);

        require(_raffleId < rafflesCount, "Invalid raffle ID");

        (, , BansheesRaffle.RaffleState raffleState) = bansheesRaffle
            .getRafflesInfo(_raffleId);
        require(
            raffleState == BansheesRaffle.RaffleState.Open,
            "Raffle not open"
        );

        bansheesRaffle.setRaffleStatusCalculating(_raffleId);

        uint256 requestId = requestRandomWords();

        statuses[requestId] = RaffleStatus({
            randomWord: 0,
            fulfilled: false,
            winner: address(0),
            raffleId: _raffleId
        });

        return requestId;
    }

    function requestRandomWords() internal returns (uint256 requestId) {
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        return requestId;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        uint256 raffleId = statuses[_requestId].raffleId;

        (
            BansheesRaffle.RaffleState raffleState,
            address[] memory tickets
        ) = bansheesRaffle.getRafflesInfoTickets(raffleId);

        require(
            raffleState == BansheesRaffle.RaffleState.Calculating,
            "Raffle not calc"
        );

        statuses[_requestId].fulfilled = true;

        uint256 indexOfWinner = _randomWords[0] % tickets.length;
        address recentWinner = tickets[indexOfWinner];

        bansheesRaffle.sendRafflePrize(recentWinner, raffleId);

        statuses[_requestId].winner = recentWinner;
        emit WinnerPicked(recentWinner);
    }
}
