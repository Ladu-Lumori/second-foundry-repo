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

pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title A raffle smart contract
 * @author Ladu Lumori
 * @notice This is an implementation of a raffle contract
 * @dev Implements Chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {
    // errors
    error Raffle__SendMoreToEnter();
    error Raffle__TransferFailed();
    error Raffle__NotOpen();
    error Raffle__NotUpKeepNeeded(uint256 balance, uint256 playersLength, uint256 raffleState);

    // type declarations
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    // state declarations
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval; // @dev duration in seconds between lotteries
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] s_players;
    uint256 private s_timeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_timeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    // CEI: Checks(Some form of condition) Effects(Internal Contract State) Interactions(External Contract Interactions) pattern; (for functions)
    function enterRaffle() external payable {
        // Checks
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__NotOpen();
        }

        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnter();
        }

        //Effects
        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev This is a function the chainlink nodes will call to see if the lottery is ready to have a winner picked.
     * The following should be true inorder for upKeepNeeded to be true:
     * 1. The time interval has passed between raffle runs
     * 2. The lottery is open
     * 3. The contract has ETH
     * 4. Implicitly, the subscription has LINK
     * @param - ignored
     * @return upKeepNeeded - true if its time to restart the lottery
     * @return - ignored
     */
    function checkUpKeep(bytes memory /* checkData */ )
        public
        view
        returns (bool upKeepNeeded, bytes memory /* performData */ )
    {
        bool timeHasPassed = ((block.timestamp - s_timeStamp) >= i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasFunds = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upKeepNeeded = timeHasPassed && isOpen && hasFunds && hasPlayers;
        return (upKeepNeeded, "");
    }

    function performUpKeep(bytes calldata /* performData */ ) external {
        // Checks
        (bool upKeepNeeded,) = checkUpKeep("");
        if (!upKeepNeeded) {
            revert Raffle__NotUpKeepNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        // Effects
        s_raffleState = RaffleState.CALCULATING;

        // Interactions
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );

        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(uint256, /*requestId*/ uint256[] calldata randomWords) internal override {
        // Checks

        // Effects
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_timeStamp = block.timestamp;
        emit WinnerPicked(s_recentWinner);

        // Intercations
        (bool success,) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    // go-getters
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayers(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_timeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}