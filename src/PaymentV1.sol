// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "aave/aave-v3-core/contracts/interfaces/IPool.sol";

contract USDCPayment {
    using SafeERC20 for IERC20;

    mapping(bytes32 => uint256) public s_transactions; // list of amounts per ID

    IPool public immutable i_pool;
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
        i_pool = IPool(_addressPool);
        i_usdc = IERC20(_usdcAddress);
        i_usdc.safeIncreaseAllowance(_addressPool, type(uint256).max);
        team_wallet = _teamAddress;
    }

    function openProposal(uint256 _amount) external {
        if (_amount == 0) revert AmountIsZero();

        if (!i_usdc.transferFrom(msg.sender, address(this), _amount)) {
            revert TransferFailed();
        }
        bytes32 uniqueId = generateID(msg.sender, _amount);

        s_transactions[uniqueId] = _amount;
        i_pool.supply(address(i_usdc), _amount, address(this), 0);

        emit ProposalOpened(uniqueId, _amount, msg.sender);
    }

    /// @param id Generated ID to ensure is caller is valid owner.
    /// @param freelancer address of beneficiary for succesfull job or empty address in case of calling by client
    function closeProposal(bytes32 id, address freelancer) external {
        uint256 proposalAmount = s_transactions[id];
        if (proposalAmount == 0) {
            revert IncorrectAmountId();
        }
        delete s_transactions[id];

        address receiver;
        if (freelancer == address(0)) {
            receiver = msg.sender;
        } else {
            receiver = freelancer;
        }

        emit ProposalClosed(id, freelancer);

        i_pool.withdraw(address(i_usdc), proposalAmount, receiver);
    }

    function withdrawUSDC(uint256 _amount) public onlyTeam {
        (uint256 totalCollateralBase, , , , , ) = i_pool.getUserAccountData(
            address(this)
        ); // get all lended money from AAVE Pool
        if (_amount > totalCollateralBase) {
            revert IncorrectAmount(_amount);
        }
        i_pool.withdraw(address(i_usdc), _amount, msg.sender);

        emit WithdrawUSDC(msg.sender, _amount);
    }

    function withdrawETH() public onlyTeam {
        uint256 balance = address(this).balance;
        (bool success, ) = msg.sender.call{value: balance}("");
        if (!success) {
            revert TransferFailed();
        }

        emit WithdrawETH(msg.sender, balance);
    }

    function changeTeamWallet(address _newTeamWallet) public onlyTeam {
        team_wallet = _newTeamWallet;
        emit WalletChanged(team_wallet, _newTeamWallet);
    }

    function getBalance(address _tokenAddress) external view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    // generate unique Indetifier for cross-chain transaction
    /// @param _beneficiary The address of the client.
    function generateID(
        address _beneficiary,
        uint256 _amount
    ) public view returns (bytes32) {
        return
            keccak256(abi.encodePacked(_beneficiary, _amount, block.timestamp));
    }

    receive() external payable {}
}
