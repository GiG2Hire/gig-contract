// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IComet} from "./interfaces/IComet.sol";

contract UsdcLiquidityCompound {
    using SafeERC20 for IERC20;

    mapping(bytes32 => uint256) public s_transactions; // list of amounts per ID

    IComet public immutable i_comet;
    IERC20 public immutable i_usdc;

    address public team_wallet; // safe wallet address

    error AmountIsZero();
    error IncorrectAmount(uint256 amount);
    error TransferFailed();
    error IncorrectTokenAmount();
    error IncorrectAmountId();
    error NotOwner();
    error InvalidUsdcToken();
    error IncorrectWalletAddress();

    event ProposalOpened(bytes32 id, uint256 amount, address initiator);
    event ProposalClosed(bytes32 id, address freelancer);
    event WalletChanged(address curr_wallet, address new_wallet);
    event WithdrawUSDC(address receiver, uint256 amount);
    event WithdrawETH(address receiver, uint256 amount);

    modifier onlyTeam() {
        if (msg.sender != team_wallet) {
            revert IncorrectWalletAddress();
        }
        _;
    }

    constructor(
        address _addressPool,
        address _usdcAddress,
        address _teamAddress
    ) {
        if (_usdcAddress == address(0)) revert InvalidUsdcToken();
        i_comet = IComet(_addressPool);
        i_usdc = IERC20(_usdcAddress);
        i_usdc.safeIncreaseAllowance(_addressPool, type(uint256).max);
        team_wallet = _teamAddress;
    }

    /// @param _amount Amount of tokens that Client supply for Job Proposal
    function openProposal(uint256 _amount) external {
        if (_amount == 0) revert AmountIsZero();

        if (!i_usdc.transferFrom(msg.sender, address(this), _amount)) {
            revert TransferFailed();
        }
        bytes32 uniqueId = generateID(msg.sender, _amount);

        s_transactions[uniqueId] = _amount;
        i_comet.supply(address(i_usdc), _amount);

        emit ProposalOpened(uniqueId, _amount, msg.sender);
    }

    /// @param _id Generated ID to ensure is caller is valid owner.
    /// @param _freelancerAddr address of beneficiary for succesfull job or empty address in case of calling by client
    function closeProposal(bytes32 _id, address _freelancerAddr) external {
        uint256 jobAmount = s_transactions[_id] - 1;

        if (jobAmount == 0) {
            revert IncorrectAmountId();
        }

        delete s_transactions[_id];
        address receiverAddr;

        if (_freelancerAddr == address(0)) {
            receiverAddr = msg.sender;
        } else {
            receiverAddr = _freelancerAddr;
        }

        i_comet.withdrawTo(receiverAddr, address(i_usdc), jobAmount);
        emit ProposalClosed(_id, receiverAddr);
    }

    // withdraw all USDC tokens from contract. Only called by previous team wallet.
    function withdrawUSDC(uint256 _amount) public onlyTeam {
        uint256 contractBalance = getBalance(address(i_usdc)); // get all lended money from Compound Pool

        uint256 suppliedTokens = getSupplyBalance();
        if (suppliedTokens > 0) {
            i_comet.withdraw(address(i_usdc), suppliedTokens);
        }

        if (_amount > contractBalance) {
            revert IncorrectAmount(_amount);
        }

        i_usdc.safeTransfer(msg.sender, _amount);
        emit WithdrawUSDC(msg.sender, _amount);
    }

    // withdraw all USDC tokens from contract. Only called by previous team wallet.
    function withdrawETH() public onlyTeam {
        uint256 balance = address(this).balance;

        (bool success, ) = msg.sender.call{value: balance}("");
        if (!success) {
            revert TransferFailed();
        }

        emit WithdrawETH(msg.sender, balance);
    }

    // change wallet address for team. Only called by previous team wallet.
    function changeTeamWallet(address _newTeamWallet) public onlyTeam {
        address prev_wallet = team_wallet;
        team_wallet = _newTeamWallet;

        emit WalletChanged(prev_wallet, _newTeamWallet);
    }

    // return rate for USDC in percentages.
    function getSupplyRate(uint _utilization) external view returns (uint256) {
        uint256 secondsPerYear = 365 * 24 * 60 * 60;
        uint64 rate = i_comet.getSupplyRate(_utilization);

        uint256 supplyAPR = (rate / (10 ** 18)) * secondsPerYear * 100;
        return supplyAPR;
    }

    // return total balance of supplied USDC to contract.
    function getSupplyBalance() public view returns (uint256) {
        return i_comet.balanceOf(address(this));
    }

    // get balance of token.
    function getBalance(address _tokenAddress) public view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    // generate unique Indetifier for transaction
    /// @param _beneficiary The address of the client that post a Job Proposal.
    function generateID(
        address _beneficiary,
        uint256 _amount
    ) private view returns (bytes32) {
        return
            keccak256(abi.encodePacked(_beneficiary, _amount, block.timestamp));
    }

    receive() external payable {}
}
