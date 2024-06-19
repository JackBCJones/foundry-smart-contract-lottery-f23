// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFCoordinatorV2Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A sample Raffle Contract
 * @author Jack Jones
 * @notice This contract is for creating a sample raffle
 * @dev Implements Chainlink VRFv2
 */

contract Raffle is VRFConsumerBaseV2 {
    // errors
    error Raffle_NotEnoughEth__Error();
    error Raffle_TooSoon__Error();
    error Raffle_TransferFailed__Error();
    error Raffle_RaffleNotOpen__Error();
    error Raffle_UpkeepNotNeeded__Error(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    // State variables
    uint32 private constant NUM_WORDS = 1;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;

    uint256 private immutable i_entranceFee;
    // @dev Duration of the lottery in seconds.
    uint256 private immutable i_interval;

    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    bytes32 private immutable i_gasLane;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recent_winner;
    RaffleState private s_raffleState;

    // Events
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    // Accept incoming payments for a certain price.
    function enterRaffle() external payable {
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle_RaffleNotOpen__Error();
        }
        if (msg.value < i_entranceFee) {
            revert Raffle_NotEnoughEth__Error();
        }
        // Assign the player to an array ticket holders.
        s_players.push(payable(msg.sender));
        // Events Make migration easier
        // and Make front end "indexing" easier.
        emit EnteredRaffle(msg.sender);
    }

    // At a point in time randomly select a user from the list.
    // 1. Get a random number from chainlink.
    // 2. Use random number to selct a player.
    // 3 Make sure this function is called automatically.
    /**
     * @dev This is the function that the chainlink automation nodes call
     * to see if it's time to perform an upkeep.
     * The following should be true for this to return true:
     * 1. The time interval has passed between raffle runs
     * 2. the raffle is in the OPEN state.
     * 3. The contract has ETH (aka, players)
     * 4. (Implicit) The subscription is funded with LINK
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasPlayers && hasBalance);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle_UpkeepNotNeeded__Error(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        // Get a random number:
        /* uint256 requestId = */ i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            uint64(i_subscriptionId),
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
    }

    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        // checks = require (if -> errors)
        // Effects = our own contract
        uint256 indexOfWinnder = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinnder];
        s_recent_winner = winner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit PickedWinner(winner);
        // Interactions (other contracts)
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle_TransferFailed__Error();
        }
    }

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_recent_winner;
    }

    function getLengthOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
