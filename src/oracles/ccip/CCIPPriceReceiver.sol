// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";

// PriceOracle contract interface
interface IPriceOracle {
    function updateIndexPriceFromStreams(uint256 price) external;
    function setAuthorized(address _account, bool _authorized) external;
}

/**
 * @title CCIPPriceReceiver
 * @notice CCIP receiver contract that integrates with PriceOracle to receive XAU/USD price data
 * This contract receives price data from Sepolia and updates the PriceOracle contract
 */
contract CCIPPriceReceiver is CCIPReceiver {
    // PriceOracle contract address
    IPriceOracle public priceOracle;
    
    // Source chain selector (Sepolia)
    uint64 public sourceChainSelector;
    
    // Source contract address on Sepolia
    address public sourceContract;
    
    // Latest received price data
    uint256 public latestReceivedPrice;
    uint256 public latestReceivedTimestamp;
    
    // Events
    event PriceReceived(uint256 price, uint256 timestamp, uint64 sourceChainSelector, address sourceContract);
    event PriceOracleUpdated(uint256 price, uint256 timestamp);
    event PriceOracleSet(address indexed priceOracle);
    event SourceChainUpdated(uint64 oldSelector, uint64 newSelector);
    event SourceContractUpdated(address oldContract, address newContract);
    event RelayCompleted(uint256 requestId, uint256 price, uint256 timestamp);
    
    // Errors
    error InvalidSourceChain(uint64 sourceChainSelector);
    error InvalidSender(address sender);
    error PriceOracleNotSet();
    error PriceUpdateFailed();
    
    /**
     * @notice Constructor
     * @param _router CCIP router address
     * @param _sourceChainSelector Source chain selector (Sepolia: 16015286601757825753)
     * @param _sourceContract Source contract address on Sepolia
     */
    constructor(
        address _router,
        uint64 _sourceChainSelector,
        address _sourceContract
    ) CCIPReceiver(_router) {
        sourceChainSelector = _sourceChainSelector;
        sourceContract = _sourceContract;
    }
    
    /**
     * @notice Handle the received message from CCIP
     * @param message The CCIP message containing the price data
     */
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        // Verify the source chain
        if (message.sourceChainSelector != sourceChainSelector) {
            revert InvalidSourceChain(message.sourceChainSelector);
        }
        
        // Verify the sender
        address sender = abi.decode(message.sender, (address));
        if (sender != sourceContract) {
            revert InvalidSender(sender);
        }
        
        // Decode the price data (price, timestamp, requestId)
        (uint256 price, uint256 timestamp, uint256 requestId) = abi.decode(message.data, (uint256, uint256, uint256));
        
        // Store the received price data
        latestReceivedPrice = price;
        latestReceivedTimestamp = timestamp;
        
        emit PriceReceived(price, timestamp, message.sourceChainSelector, sender);
        
        // Update the PriceOracle contract if it's set
        if (address(priceOracle) != address(0)) {
            try priceOracle.updateIndexPriceFromStreams(price) {
                emit PriceOracleUpdated(price, timestamp);
                
                // Emit relay completion event for tracking
                emit RelayCompleted(requestId, price, timestamp);
            } catch {
                revert PriceUpdateFailed();
            }
        }
    }
    
    /**
     * @notice Set the PriceOracle contract address
     * @param _priceOracle Address of the PriceOracle contract
     */
    function setPriceOracle(address _priceOracle) external {
        priceOracle = IPriceOracle(_priceOracle);
        emit PriceOracleSet(_priceOracle);
    }
    
    /**
     * @notice Update the source chain selector
     * @param _sourceChainSelector New source chain selector
     */
    function setSourceChainSelector(uint64 _sourceChainSelector) external {
        uint64 oldSelector = sourceChainSelector;
        sourceChainSelector = _sourceChainSelector;
        emit SourceChainUpdated(oldSelector, _sourceChainSelector);
    }
    
    /**
     * @notice Update the source contract address
     * @param _sourceContract New source contract address
     */
    function setSourceContract(address _sourceContract) external {
        address oldContract = sourceContract;
        sourceContract = _sourceContract;
        emit SourceContractUpdated(oldContract, _sourceContract);
    }
    
    /**
     * @notice Get the latest received price data
     */
    function getLatestReceivedPrice() external view returns (uint256 price, uint256 timestamp) {
        return (latestReceivedPrice, latestReceivedTimestamp);
    }
    
    /**
     * @notice Manually update PriceOracle with the latest received price
     * This can be used if the automatic update fails
     */
    function manualUpdatePriceOracle() external {
        if (address(priceOracle) == address(0)) {
            revert PriceOracleNotSet();
        }
        
        if (latestReceivedPrice == 0) {
            revert("No price data received");
        }
        
        priceOracle.updateIndexPriceFromStreams(latestReceivedPrice);
        emit PriceOracleUpdated(latestReceivedPrice, latestReceivedTimestamp);
    }
    
    /**
     * @notice Withdraw ETH from this contract
     */
    function withdrawEth() external {
        uint256 amount = address(this).balance;
        if (amount == 0) revert("Nothing to withdraw");
        
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert("Failed to withdraw ETH");
    }
    
    // Allow the contract to receive ETH
    receive() external payable {}
} 