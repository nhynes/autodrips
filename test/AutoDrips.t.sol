// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";

import {AddressDriver} from "drips-contracts/AddressDriver.sol";
import {
    Drips,
    MaxEndHints,
    MaxEndHintsImpl,
    SplitsReceiver,
    StreamReceiver,
    StreamConfigImpl
} from "drips-contracts/Drips.sol";
import {Managed, ManagedProxy} from "drips-contracts/Managed.sol";
import {ERC20, IERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

import {AutoDripsDriver, ImpactListId} from "../src/AutoDripsDriver.sol";

contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AutoDripsTest is Test {
    Drips public drips;
    AddressDriver public addressDriver;

    AutoDripsDriver public autodrips;

    address internal receiver1 = address(0x4200);
    address internal receiver2 = address(0x4201);
    address internal receiver3 = address(0x4202);

    MockToken internal mockToken;

    function setUp() public {
        Drips dripsLogic = new Drips(10);
        drips = Drips(address(new ManagedProxy(dripsLogic, address(this))));

        AddressDriver addressDriverLogic =
            new AddressDriver(drips, address(0), drips.nextDriverId());
        addressDriver = AddressDriver(address(new ManagedProxy(addressDriverLogic, address(1))));
        drips.registerDriver(address(addressDriver));

        mockToken = new MockToken();
        mockToken.mint(address(this), 10_000_000 ether);

        AutoDripsDriver autodripsLogic =
            new AutoDripsDriver(drips, drips.nextDriverId(), address(0), mockToken);
        autodrips = AutoDripsDriver(address(new ManagedProxy(autodripsLogic, address(this))));
        drips.registerDriver(address(autodrips));
    }

    function test_workflow() public {
        ImpactListId impactList = ImpactListId.wrap(1);
        IERC20 erc20 = IERC20(address(mockToken));
        MaxEndHints hints = MaxEndHintsImpl.create();

        autodrips.setOracle(address(this));
        autodrips.setReceivers(
            impactList, _receivers(false, false, false), _receivers(true, true, false), hints
        );

        mockToken.approve(address(autodrips), 100 ether);
        autodrips.donate(impactList, erc20, 100 ether, _receivers(true, true, false), hints);

        uint32 numCycles = 123;
        vm.warp(block.timestamp + numCycles * drips.cycleSecs());

        assertEq(
            drips.receiveStreams(addressDriver.calcAccountId(receiver1), erc20, numCycles), 1229
        );
        assertEq(
            drips.receiveStreams(addressDriver.calcAccountId(receiver2), erc20, numCycles), 1229 * 2
        );
        assertEq(drips.receiveStreams(addressDriver.calcAccountId(receiver3), erc20, numCycles), 0);

        autodrips.setReceivers(
            impactList, _receivers(true, true, false), _receivers(false, false, true), hints
        );
        vm.warp(block.timestamp + numCycles * drips.cycleSecs());

        assertEq(
            drips.receiveStreams(addressDriver.calcAccountId(receiver1), erc20, numCycles),
            1 // residual
        );
        assertEq(
            drips.receiveStreams(addressDriver.calcAccountId(receiver2), erc20, numCycles),
            2 // residual
        );
        assertEq(
            drips.receiveStreams(addressDriver.calcAccountId(receiver3), erc20, numCycles), 1229 * 3
        );

        autodrips.setReceivers(
            impactList, _receivers(false, false, true), _receivers(false, false, false), hints
        );
        vm.warp(block.timestamp + numCycles * drips.cycleSecs());
        assertEq(
            drips.receiveStreams(addressDriver.calcAccountId(receiver3), erc20, numCycles),
            3 // residual
        );

        drips.split(addressDriver.calcAccountId(receiver1), erc20, new SplitsReceiver[](0));
        drips.split(addressDriver.calcAccountId(receiver2), erc20, new SplitsReceiver[](0));
        drips.split(addressDriver.calcAccountId(receiver3), erc20, new SplitsReceiver[](0));

        vm.prank(receiver1);
        addressDriver.collect(erc20, receiver1);
        assertEq(erc20.balanceOf(receiver1), numCycles * drips.cycleSecs());

        vm.prank(receiver2);
        addressDriver.collect(erc20, receiver2);
        assertEq(erc20.balanceOf(receiver2), numCycles * 2 * drips.cycleSecs());

        vm.prank(receiver3);
        addressDriver.collect(erc20, receiver3);
        assertEq(erc20.balanceOf(receiver3), numCycles * 3 * drips.cycleSecs());
    }

    function _receivers(bool one, bool two, bool three)
        internal
        view
        returns (StreamReceiver[] memory receivers)
    {
        receivers = new StreamReceiver[]((one ? 1 : 0) + (two ? 1 : 0) + (three ? 1 : 0));
        uint256 i;
        if (one) {
            receivers[i] = StreamReceiver({
                accountId: addressDriver.calcAccountId(receiver1),
                config: StreamConfigImpl.create(0, 1 * drips.AMT_PER_SEC_MULTIPLIER(), 0, 0)
            });
            i++;
        }
        if (two) {
            receivers[i] = StreamReceiver({
                accountId: addressDriver.calcAccountId(receiver2),
                config: StreamConfigImpl.create(0, 2 * drips.AMT_PER_SEC_MULTIPLIER(), 0, 0)
            });
            i++;
        }
        if (three) {
            receivers[i] = StreamReceiver({
                accountId: addressDriver.calcAccountId(receiver3),
                config: StreamConfigImpl.create(0, 3 * drips.AMT_PER_SEC_MULTIPLIER(), 0, 0)
            });
            i++;
        }
    }
}
