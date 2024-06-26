// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {console2} from "forge-std/console2.sol";

import {Drips, MaxEndHints, StreamReceiver, IERC20} from "drips-contracts/Drips.sol";
import {DriverTransferUtils} from "drips-contracts/DriverTransferUtils.sol";
import {Managed} from "drips-contracts/Managed.sol";

type ImpactListId is uint256;

contract AutoDripsDriver is DriverTransferUtils, Managed {
    event ReceiversUpdated(ImpactListId indexed impactList);

    /// @notice The Drips address used by this driver.
    Drips public immutable drips;
    /// @notice The driver ID which this driver uses when calling Drips.
    uint32 public immutable driverId;
    /// @notice The supported ERC20 token.
    /// @dev Set this to a Merkle trie hash to support multiple and allow donors to prove inclusion.
    IERC20 public immutable supportedErc20;

    address public oracle;

    modifier onlyOracle() {
        require(_msgSender() == oracle, "Caller is not the oracle");
        _;
    }

    constructor(Drips drips_, uint32 driverId_, address forwarder, IERC20 erc20)
        DriverTransferUtils(forwarder)
    {
        drips = drips_;
        driverId = driverId_;
        supportedErc20 = erc20;
    }

    function setOracle(address oracle_) external onlyProxy onlyAdmin {
        oracle = oracle_;
    }

    function setReceivers(
        ImpactListId impactList,
        StreamReceiver[] calldata currReceivers,
        StreamReceiver[] calldata newReceivers,
        MaxEndHints maxEndHints
    ) external onlyOracle {
        _setStreamsAndTransfer(
            drips,
            impactListToAccountId(impactList),
            supportedErc20,
            currReceivers,
            0,
            newReceivers,
            maxEndHints,
            address(0)
        );
        emit ReceiversUpdated(impactList);
    }

    /// @notice Donates money into the impact list's stream.
    /// Transfers funds between the message sender's wallet and the Drips contract
    /// to fulfil the change of the streams balance.
    /// @param impactList The impact list.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param receivers The current streams receivers list.
    /// It must be exactly the same as the last list set for the sender with `setStreams`.
    /// If this is the first update, pass an empty array.
    /// @param maxEndHints An optional parameter allowing gas optimization.
    /// To not use this feature pass an integer `0`, it represents a list of 8 zero value hints.
    /// This argument is a list of hints for finding the timestamp when all streams stop
    /// due to funds running out after the streams configuration is updated.
    /// Hints have no effect on the results of calling this function, except potentially saving gas.
    /// Hints are Unix timestamps used as the starting points for binary search for the time
    /// when funds run out in the range of timestamps from the current block's to `2^32`.
    /// Hints lower than the current timestamp including the zero value hints are ignored.
    /// If you provide fewer than 8 non-zero value hints make them the rightmost values to save gas.
    /// It's the most beneficial to make the most risky and precise hints
    /// the rightmost ones, but there's no strict ordering requirement.
    /// Hints are the most effective when one of them is lower than or equal to
    /// the last timestamp when funds are still streamed, and the other one is strictly larger
    /// than that timestamp, the smaller the difference between such hints, the more gas is saved.
    /// The savings are the highest possible when one of the hints is equal to
    /// the last timestamp when funds are still streamed, and the other one is larger by 1.
    /// It's worth noting that the exact timestamp of the block in which this function is executed
    /// may affect correctness of the hints, especially if they're precise,
    /// which is why you may want to pass multiple hints with varying precision.
    /// Hints don't provide any benefits when balance is not enough to cover
    /// a single second of streaming or is enough to cover all streams until timestamp `2^32`.
    /// Even inaccurate hints can be useful, and providing a single hint
    /// or hints that don't enclose the time when funds run out can still save some gas.
    /// Providing poor hints that don't reduce the number of binary search steps
    /// may cause slightly higher gas usage than not providing any hints.
    function donate(
        ImpactListId impactList,
        IERC20 erc20,
        uint256 amount,
        StreamReceiver[] calldata receivers,
        MaxEndHints maxEndHints
    ) external {
        require(erc20 == supportedErc20, "Unsupported ERC-20");
        require(amount < uint128(type(int128).max), "too much donation");
        _setStreamsAndTransfer(
            drips,
            impactListToAccountId(impactList),
            erc20,
            receivers,
            int128(uint128(amount)),
            receivers,
            maxEndHints,
            address(0)
        );
    }

    function impactListToAccountId(ImpactListId impactList)
        public
        view
        returns (uint256 accountId)
    {
        accountId = driverId;
        accountId = (accountId << 224) | ImpactListId.unwrap(impactList);
    }
}
