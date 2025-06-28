// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Chainlink, ChainlinkClient} from "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
/// @title Price Oracle using the standard Request & Receive pattern
/// @notice This contract is designed to work with a Chainlink job that does NOT
/// use the `ethtx` task. The Operator.sol contract calls `fulfill`.
contract PriceOracle is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    enum PriceType { MARK, INDEX }

    // State variables
    uint256 public linkFee = (1 * LINK_DIVISIBILITY) / 10; // 0.1 LINK
    uint256 public indexPrice;
    uint256 public indexPriceTimestamp;
    uint256 public stalePeriod;
    address public oracleAddress; // The address of the Operator.sol contract
    bytes32 public jobId; // Job ID is now bytes32
    mapping(address => bool) public isAuthorized;
    AggregatorV3Interface public priceFeed;
    uint256 public externalAdapterPrice;
    uint256 public externalAdapterTimestamp;

    // Events
    event PriceUpdated(PriceType indexed priceType, uint256 price, uint256 timestamp);
    event JobIdUpdated(bytes32 newJobId);
    event OracleAddressUpdated(address newOracle);
    event PriceRequested(bytes32 indexed requestId);
    event Trigger(); // Event to trigger Chainlink Automation upkeep
    event UpdateIndexPriceFromFeed(); // Event to update index price from feed

    constructor(
        address _linkToken,
        address _oracleAddress,
        uint256 _stalePeriod,
        address _priceFeed
    ) ConfirmedOwner(msg.sender) {
        _setChainlinkToken(_linkToken);
        oracleAddress = _oracleAddress;
        stalePeriod = _stalePeriod;
        priceFeed = AggregatorV3Interface(_priceFeed);
    }
    
    function setJobId(string calldata _jobId) external onlyOwner {
        jobId = stringToBytes32(_jobId);
        emit JobIdUpdated(jobId);
    }

    function setLinkFee(uint256 _newFee) external onlyOwner {
        linkFee = _newFee;
    }
    
    function setOracleAddress(address _newOracle) external onlyOwner {
        oracleAddress = _newOracle;
        emit OracleAddressUpdated(_newOracle);
    }

    function setStalePeriod(uint256 _newStalePeriod) external onlyOwner {
        stalePeriod = _newStalePeriod;
    }

    function getIndexPrice() external view returns (uint256 price, uint256 timestamp) {
        return (indexPrice, indexPriceTimestamp);
    }

    function isIndexPriceStale() public view returns (bool) {
        return block.timestamp > indexPriceTimestamp + stalePeriod;
    }

    /// @notice Requests the index price from the Chainlink network.
    function requestIndexPrice() public {
        require(jobId[0] != 0, "Job ID not set");
        Chainlink.Request memory req = _buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfillRequest.selector
        );
        bytes32 requestId = _sendChainlinkRequestTo(oracleAddress, req, linkFee);
        emit PriceRequested(requestId);
    }

    /// @notice The callback function called by the Operator contract
    function fulfillRequest(bytes32 _requestId, uint256 _price) public recordChainlinkFulfillment(_requestId) {
        indexPrice = _price;
        indexPriceTimestamp = block.timestamp;
        emit PriceUpdated(PriceType.INDEX, _price, block.timestamp);
    }

    /// @notice Allows the owner to withdraw any LINK balance from the contract
    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(_chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
    }

    /// @notice For emergency use, allows owner to cancel a request
    function cancelRequest(bytes32 _requestId, uint256 _payment, bytes4 _callbackFunctionId, uint256 _expiration) public onlyOwner {
        _cancelChainlinkRequest(_requestId, _payment, _callbackFunctionId, _expiration);
    }

    /// @dev Converts a string to bytes32.
    function stringToBytes32(string memory source) private pure returns (bytes32 result) {
        bytes memory temp = bytes(source);
        if (temp.length == 0) return 0x0;
        assembly {
            result := mload(add(source, 32))
        }
    }

    function updateIndexPriceFromFeed() public onlyAuthorized {
        // emit event for offchain cron to update index price
        emit UpdateIndexPriceFromFeed();
    }

    // --- Main Data Streams update (only StreamUpkeep/authorized) ---
    function updateIndexPriceFromStreams(uint256 price) external onlyAuthorized {
        indexPrice = price;
        indexPriceTimestamp = block.timestamp;
        emit PriceUpdated(PriceType.INDEX, price, block.timestamp);
    }

    // --- Emit log for StreamUpkeep (called by off-chain cron) ---
    function triggerStreamUpkeep() public {
        emit Trigger();
    }

    modifier onlyAuthorized() {
        require(isAuthorized[msg.sender], "Not authorized");
        _;
    }

    function setAuthorized(address _account, bool _authorized) external onlyOwner {
        isAuthorized[_account] = _authorized;
    }

    function refreshIndexPrice() external onlyAuthorized {
        // 1. If not stale, trigger StreamUpkeep and return
        if (!isIndexPriceStale()) {
            triggerStreamUpkeep();
            return;
        }
        // 2. If stale, try to update from direct request
        requestIndexPrice();

        // 3. If still stale after feed update, fallback to feed
        if (isIndexPriceStale()) {
            updateIndexPriceFromFeed();
        }
    }

    function getLinkFee() external view returns (uint256) { return linkFee; }
    function getOracleAddress() external view returns (address) { return oracleAddress; }
    function getJobId() external view returns (bytes32) { return jobId; }
    function getStalePeriod() external view returns (uint256) { return stalePeriod; }
    function getPriceFeed() external view returns (address) { return address(priceFeed); }
    function setPriceFeed(address _priceFeed) external onlyOwner { priceFeed = AggregatorV3Interface(_priceFeed); }

} 