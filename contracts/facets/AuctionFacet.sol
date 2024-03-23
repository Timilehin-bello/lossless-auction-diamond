// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibAppStorage} from "../libraries/LibAppStorage.sol";
import {IERC721} from "../interfaces/IERC721.sol";
import {IERC165} from "../interfaces/IERC165.sol";
import {IERC1155} from "../interfaces/IERC1155.sol";

/**
 * @title AuctionFacet
 * @dev The AuctionFacet is a facet of the Diamond that handles auctions for NFTs
 * It uses the Diamond Standard and Diamond Cuttable to store data
 * It uses the DiamondLoupeFacet to get data from the Diamond
 */
contract AuctionFacet {
    /**
     * @dev The storage slot for the AuctionFacet is the keccak256 hash of "AuctionFacet.storage"
     */
    LibAppStorage.Layout internal l;

    /**
     * @dev Create an auction for an NFT
     * @notice Only the owner of the NFT can create an auction for it.
     * @param _duration The duration of the auction in seconds
     * @param _startingBid The starting bid for the auction
     * @param _nftId The id of the NFT being auctioned off
     * @param _nftAddress The address of the NFT contract
     */
    function createAuction(
        uint256 _duration,
        uint256 _startingBid,
        uint256 _nftId,
        address _nftAddress
    ) public {
        // Check that the NFT contract supports either ERC721 or ERC1155
        require(
            IERC165(_nftAddress).supportsInterface(type(IERC721).interfaceId) ||
                IERC165(_nftAddress).supportsInterface(
                    type(IERC1155).interfaceId
                ),
            "AuctionFacet: Invalid NFT contract"
        );

        // Check that the sender is the owner of the NFT
        if (IERC165(_nftAddress).supportsInterface(type(IERC721).interfaceId)) {
            require(
                IERC721(_nftAddress).ownerOf(_nftId) == msg.sender,
                "AuctionFacet: Not owner of NFT"
            );
        } else if (
            IERC165(_nftAddress).supportsInterface(type(IERC1155).interfaceId)
        ) {
            require(
                IERC1155(_nftAddress).balanceOf(msg.sender, _nftId) > 0,
                "AuctionFacet: Not owner of NFT"
            );
        }

        // Create the auction
        uint256 auctionId = l.auctionCount + 1;
        LibAppStorage.AuctionDetails storage a = l.Auctions[auctionId];
        a.duration = _duration;
        a.startingBid = _startingBid;
        a.nftId = _nftId;
        a.nftAddress = _nftAddress;

        l.auctionCount = l.auctionCount + 1;
    }

    /**
     * @dev Place a bid on an auction
     * @notice The highest bidder must be a different address than the current highest bidder.
     * @notice The bid amount must be greater than or equal to the current bid amount.
     * @notice The auction must not have ended.
     * @notice The sender must have enough balance to place the bid.
     * @param _amount The amount the bidder is placing
     * @param _auctionId The auction ID to place the bid on
     */
    function bid(uint256 _amount, uint256 _auctionId) public {
        // Check if the sender is already the highest bidder
        LibAppStorage.AuctionDetails storage a = l.Auctions[_auctionId];
        require(
            a.highestBidder != msg.sender,
            "AuctionFacet: Already highest bidder"
        );

        // The bid amount must be greater than or equal to the current bid amount
        require(
            a.startingBid <= _amount,
            "AuctionFacet: Bid amount is less than starting bid"
        );

        // Check if the auction has ended
        require(
            a.duration > block.timestamp,
            "AuctionFacet: Auction has ended"
        );

        // Check if the user has enough balance to place the bid
        uint balance = l.balances[msg.sender];
        require(balance >= _amount, "AuctionFacet: Not enough balance to bid");

        // If this is the first bid on the auction
        if (a.currentBid == 0) {
            // Transfer the NFT to the contract
            LibAppStorage._transferFrom(msg.sender, address(this), _amount);

            // Set the highest bidder & current bid amount
            a.highestBidder = msg.sender;
            a.currentBid = _amount;

            // If there is already a bid on the auction
        } else {
            // Calculate the minimum acceptable bid
            uint check = ((a.currentBid * 20) / 100) + a.currentBid;

            // Check if the new bid is unprofitable
            if (_amount < check) {
                revert("Unprofitable Bid");
            }

            // Transfer the bid amount to the contract
            LibAppStorage._transferFrom(msg.sender, address(this), _amount);

            // Pay the previous highest bidder
            _payPreviousBidder(_auctionId, _amount, a.currentBid);

            // Set the new highest bidder & current bid amount
            a.previousBidder = a.highestBidder;
            a.highestBidder = msg.sender;
            a.currentBid = _amount;

            // Handle transaction costs
            _handleTransactionCosts(_auctionId, _amount);

            // Pay the last interactor (contract owner)
            payLastInteractor(_auctionId, a.highestBidder);
        }
    }

    /**
     * @dev Claim the reward for the auction
     * @notice Only the highest bidder can claim the reward
     * @param _auctionId The auction ID to claim the reward for
     */
    function claimReward(uint256 _auctionId) public {
        LibAppStorage.AuctionDetails storage a = l.Auctions[_auctionId];
        require(
            a.highestBidder == msg.sender,
            "AuctionFacet: Only highest bidder can claim reward"
        );
        require(
            a.duration <= block.timestamp,
            "AuctionFacet: Auction duration has not ended"
        );

        // Transfer the NFT to the winner
        if (
            IERC165(a.nftAddress).supportsInterface(type(IERC1155).interfaceId)
        ) {
            // Transfer ERC1155 token to the winner
            IERC1155(a.nftAddress).safeTransferFrom(
                address(this),
                msg.sender,
                a.nftId,
                1,
                ""
            );
        } else if (
            IERC165(a.nftAddress).supportsInterface(type(IERC721).interfaceId)
        ) {
            // Transfer ERC721 token to the winner
            IERC721(a.nftAddress).safeTransferFrom(
                address(this),
                msg.sender,
                a.nftId
            );
        } else {
            revert("AuctionFacet: Invalid NFT type");
        }
        // Reset auction details
        a.highestBidder = address(0);
        a.previousBidder = address(0);
        a.duration = 0;
        a.startingBid = 0;
        a.currentBid = 0;
        a.nftAddress = address(0);
        a.nftId = 0;
    }

    /**
     * @dev Pay the previous bidder the appropriate amount
     *
     * @notice The payment amount is calculated by multiplying the percentage of the current bid that
     * the previous bidder is entitled to, plus the previous bid. This is then transferred from the
     * auction contract to the previous bidder.
     *
     * @param _auctionId The ID of the auction
     * @param _amount The current bid amount
     * @param _previousBid The previous bid amount
     */
    function _payPreviousBidder(
        uint256 _auctionId,
        uint256 _amount,
        uint256 _previousBid
    ) private {
        LibAppStorage.AuctionDetails storage a = l.Auctions[_auctionId];
        require(
            a.previousBidder != address(0),
            "AuctionFacet: No previous bidder"
        );

        uint256 paymentAmount = ((_amount * LibAppStorage.PreviousBidder) /
            100) + _previousBid;
        LibAppStorage._transferFrom(
            address(this), // Auction contract
            a.previousBidder, // Previous bidder
            paymentAmount // Total payment amount to be transferred
        );
    }

    /**
     * @dev Pays the last interactor of an auction the 1% of the current bid.
     * @notice This function is used to pay the last interactor of an auction
     * the 1% of the current bid.
     *
     * @param _auctionId The auction Id to retrieve the previous bidder.
     * @param _lastInteractor The address of the last interactor.
     */
    function payLastInteractor(
        uint256 _auctionId,
        address _lastInteractor
    ) private {
        LibAppStorage.AuctionDetails storage a = l.Auctions[_auctionId];
        require(
            _lastInteractor != address(0),
            "AuctionFacet: No last interactor"
        );

        // Calculate the payment amount for the last interactor
        uint256 paymentAmount = (a.currentBid * 1) / 100;
        LibAppStorage._transferFrom(
            address(this), // Auction contract
            _lastInteractor, // Last interactor
            paymentAmount // Payment amount to be transferred
        );
    }

    /**
     * @dev Handles transaction costs for the auction. The costs are
     * calculated based on the given amount and the fee percentage
     * configured in the app storage library. The total amount is split
     * between Burn, DAO, and Team Wallet.
     *
     * @param _auctionId The auction Id to retrieve the previous bidder.
     * @param _amount The amount to be split.
     */
    function _handleTransactionCosts(
        uint256 _auctionId,
        uint256 _amount
    ) private {
        LibAppStorage.AuctionDetails storage a = l.Auctions[_auctionId];
        // Handle Burn
        uint256 burnAmount = (_amount * LibAppStorage.Burnable) / 100;
        LibAppStorage._transferFrom(
            address(this), // Auction contract
            a.previousBidder, // Previous bidder
            burnAmount // Burn amount to be transferred
        );

        // Handle DAO fees
        uint256 daoAmount = (_amount * LibAppStorage.DAO) / 100;
        LibAppStorage._transferFrom(
            address(this), // Auction contract
            LibAppStorage.DAOAddress, // DAO address
            daoAmount // DAO amount to be transferred
        );

        // Handle Team Wallet fees
        uint256 teamAmount = (_amount * LibAppStorage.TeamWallet) / 100;
        LibAppStorage._transferFrom(
            address(this), // Auction contract
            LibAppStorage.TeamWalletAddress, // Team Wallet address
            teamAmount // Team Wallet amount to be transferred
        );
    }
}
