// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {USDCPayment} from "../src/PaymentV1.sol";
import {IUSDC} from "../src/interfaces/IUSDC.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/contracts/token/ERC20/IERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

contract USDCPaymentTest is Test {
    USDCPayment private usdcPayment;
    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // Arbitrum mainnet USDC token
    address public constant POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD; // Arbitrum mainnet Pool
    uint256 public constant TESTING_AMOUNT = 1e6;

    function setUp() public {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));
        usdcPayment = new USDCPayment(POOL, USDC);
    }

    function mintTokens() public {
        IUSDC tempUsdc = IUSDC(USDC);
        vm.prank(tempUsdc.masterMinter());

        tempUsdc.configureMinter(address(this), type(uint256).max);
        tempUsdc.mint(address(this), TESTING_AMOUNT);
    }

    //////////////////////////
    //  Testing Functions  //
    ////////////////////////
    function test_Constructor() public view {
        assertEq(
            address(usdcPayment.i_usdc()),
            USDC,
            "Should set correct USDC address."
        );
        assertEq(
            address(usdcPayment.i_pool()),
            POOL,
            "Should set correct AAVE Pool address."
        );

        assertEq(
            IERC20(USDC).allowance(address(usdcPayment), POOL),
            type(uint256).max
        );
    }

    function test_BalanceSetCorrectly() public {
        mintTokens();

        uint256 balance = IUSDC(USDC).balanceOf(address(this));
        assertEq(
            balance,
            TESTING_AMOUNT,
            "Incorrect balanc of Caller contract."
        );
    }

    function test_ReverOpentIfBalanceIncorrect() public {
        vm.expectRevert(USDCPayment.AmountIsZero.selector);
        usdcPayment.openProposal(0);
    }

    function test_RevertIfNotApproved() public {
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        usdcPayment.openProposal(TESTING_AMOUNT);
    }

    function test_CallSupplyIfSucces() public {
        mintTokens();

        vm.expectCall(
            POOL,
            abi.encodeCall(
                IPool.supply,
                (USDC, TESTING_AMOUNT, address(usdcPayment), 0)
            )
        );

        IERC20(USDC).approve(address(usdcPayment), TESTING_AMOUNT);
        usdcPayment.openProposal(TESTING_AMOUNT);
    }

    function test_EmitOpenIfSuccess() public {
        mintTokens();

        bytes32 id = usdcPayment.generateID(address(this), TESTING_AMOUNT);
        IERC20(USDC).approve(address(usdcPayment), TESTING_AMOUNT);

        vm.expectEmit();
        emit USDCPayment.ProposalOpened(id, TESTING_AMOUNT, address(this));

        usdcPayment.openProposal(TESTING_AMOUNT);
    }

    function test_SetBalanceAfterCall() public {
        mintTokens();

        uint256 initAmount = IERC20(USDC).balanceOf(address(this));
        assertEq(initAmount, 1e6, "Amount minted incorrect.");

        IERC20(USDC).approve(address(usdcPayment), TESTING_AMOUNT);
        usdcPayment.openProposal(TESTING_AMOUNT);

        uint256 newAmount = IERC20(USDC).balanceOf(address(this));
        assertEq(newAmount, 0, "Amount must be zero.");
    }

    function test_SetMappingBalance() public {
        mintTokens();

        bytes32 id = usdcPayment.generateID(address(this), TESTING_AMOUNT);

        IERC20(USDC).approve(address(usdcPayment), TESTING_AMOUNT);
        usdcPayment.openProposal(TESTING_AMOUNT);

        assertEq(
            vm.getBlockTimestamp(),
            block.timestamp,
            "Incorrect block timestamp."
        );
        assertEq(
            usdcPayment.s_transactions(id),
            TESTING_AMOUNT,
            "Incorrect setted value."
        );
    }

    function test_OpenAndCloseProposalByClient() public {
        mintTokens();

        bytes32 id = usdcPayment.generateID(address(this), TESTING_AMOUNT);

        IERC20(USDC).approve(address(usdcPayment), TESTING_AMOUNT);

        usdcPayment.openProposal(TESTING_AMOUNT);
        assertEq(
            IERC20(USDC).balanceOf(address(this)),
            0,
            "Incorrect User balance."
        );

        usdcPayment.closeProposal(id, address(this));
        assertEq(
            IERC20(USDC).balanceOf(address(this)),
            TESTING_AMOUNT,
            "Incorrect User balance."
        );
    }

    function test_RevertCloseIfBalanceIncorrect() public {
        mintTokens();

        // incorrect id
        bytes32 tempId = usdcPayment.generateID(
            address(this),
            TESTING_AMOUNT + 1
        );
        IERC20(USDC).approve(address(usdcPayment), TESTING_AMOUNT);

        usdcPayment.openProposal(TESTING_AMOUNT);
        vm.expectRevert();
        usdcPayment.closeProposal(tempId, address(this));

        assertEq(usdcPayment.s_transactions(tempId), 0);
    }

    function test_CallWithdrawIfSuccess() public {
        mintTokens();

        bytes32 id = usdcPayment.generateID(address(this), TESTING_AMOUNT);
        vm.expectCall(
            POOL,
            abi.encodeCall(
                IPool.withdraw,
                (USDC, TESTING_AMOUNT, address(this))
            )
        );

        IERC20(USDC).approve(address(usdcPayment), TESTING_AMOUNT);

        usdcPayment.openProposal(TESTING_AMOUNT);
        usdcPayment.closeProposal(id, address(this));
    }

    function test_EmitCloseIfSuccess() public {
        mintTokens();

        bytes32 id = usdcPayment.generateID(address(this), TESTING_AMOUNT);
        IERC20(USDC).approve(address(usdcPayment), TESTING_AMOUNT);
        usdcPayment.openProposal(TESTING_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit USDCPayment.ProposalClosed(id, address(this));

        usdcPayment.closeProposal(id, address(this));
    }

    function test_TransferTokensToFreelancer() public {
        mintTokens();

        address freelancer = makeAddr("test_freelancer");
        bytes32 id = usdcPayment.generateID(address(this), TESTING_AMOUNT);

        uint256 initBalance = IERC20(USDC).balanceOf(freelancer);
        assertEq(initBalance, 0, "Incorrect Freelancer initial balance.");

        IERC20(USDC).approve(address(usdcPayment), TESTING_AMOUNT);

        usdcPayment.openProposal(TESTING_AMOUNT);
        usdcPayment.closeProposal(id, freelancer);

        uint256 finishedBalance = IERC20(USDC).balanceOf(freelancer);
        assertEq(
            finishedBalance,
            TESTING_AMOUNT,
            "Incorrect Freelancer balance after Job succesfully submited."
        );
        assertEq(
            usdcPayment.s_transactions(id),
            0,
            "Need to delete proposal budget after closing."
        );
    }
}
