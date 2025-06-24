// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Credra is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum EscrowStatus { Locked, Refunded, Released, Cancelled, Disputed }

    struct EscrowPayment {
        address sender;
        address recipient;
        address token;
        uint256 amount;
        uint40 startTime;
        uint40 disputeRaisedAt;
        EscrowStatus status;
    }

    mapping(bytes32 => EscrowPayment) public escrows;
    mapping(address => bool) public allowedTokens;
    address public owner;

    // Events
    event PaymentInitiated(bytes32 indexed escrowId, address indexed sender, address indexed recipient, address token, uint256 amount);
    event RefundIssued(bytes32 indexed escrowId);
    event EscrowCancelled(bytes32 indexed escrowId);
    event DisputeRaised(bytes32 indexed escrowId);
    event PaymentReleased(bytes32 indexed escrowId);

    // Custom errors
    error Unauthorized();
    error InvalidToken();
    error ZeroAmount();
    error EscrowIdExists();
    error InvalidRecipient();
    error EscrowNotFound();
    error InvalidStatus();
    error DisputeTooSoon();
    error AlreadyDisputed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Add a token to allowed list
    function addAllowedToken(address _token) external onlyOwner {
        allowedTokens[_token] = true;
    }

    /// @notice Initiate a payment (escrowed)
    function pay(address _token, uint256 _amount, address _recipient, bytes32 _escrowId) external nonReentrant {
        if (!allowedTokens[_token]) revert InvalidToken();
        if (_amount == 0) revert ZeroAmount();
        if (escrows[_escrowId].amount != 0) revert EscrowIdExists();
        if (_recipient == address(0)) revert InvalidRecipient();

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        escrows[_escrowId] = EscrowPayment({
            sender: msg.sender,
            recipient: _recipient,
            token: _token,
            amount: _amount,
            startTime: uint40(block.timestamp),
            disputeRaisedAt: 0,
            status: EscrowStatus.Locked
        });

        emit PaymentInitiated(_escrowId, msg.sender, _recipient, _token, _amount);
    }

    /// @notice Raise a dispute (by sender or recipient)
    function raiseDispute(bytes32 _escrowId) external {
        EscrowPayment storage escrow = escrows[_escrowId];
        if (escrow.amount == 0) revert EscrowNotFound();
        if (msg.sender != escrow.sender && msg.sender != escrow.recipient) revert Unauthorized();
        if (escrow.status != EscrowStatus.Locked) revert InvalidStatus();
        if (escrow.disputeRaisedAt != 0) revert AlreadyDisputed();

        escrow.disputeRaisedAt = uint40(block.timestamp);
        escrow.status = EscrowStatus.Disputed;

        emit DisputeRaised(_escrowId);
    }

    /// @notice Cancel a payment (only by sender, if not disputed)
    function cancel(bytes32 _escrowId) external nonReentrant {
        EscrowPayment storage escrow = escrows[_escrowId];
        if (escrow.amount == 0) revert EscrowNotFound();
        if (escrow.sender != msg.sender) revert Unauthorized();
        if (escrow.status != EscrowStatus.Locked) revert InvalidStatus();

        escrow.status = EscrowStatus.Cancelled;
        IERC20(escrow.token).safeTransfer(escrow.sender, escrow.amount);

        emit EscrowCancelled(_escrowId);
    }

    /// @notice Refund payment (only owner)
    function refund(bytes32 _escrowId) external onlyOwner nonReentrant {
        EscrowPayment storage escrow = escrows[_escrowId];
        if (escrow.amount == 0) revert EscrowNotFound();
        if (escrow.status != EscrowStatus.Disputed) revert InvalidStatus();

        escrow.status = EscrowStatus.Refunded;
        IERC20(escrow.token).safeTransfer(escrow.sender, escrow.amount);

        emit RefundIssued(_escrowId);
    }

    /// @notice Release payment to recipient (only owner)
    function release(bytes32 _escrowId) external onlyOwner nonReentrant {
        EscrowPayment storage escrow = escrows[_escrowId];
        if (escrow.amount == 0) revert EscrowNotFound();
        if (escrow.status != EscrowStatus.Disputed) revert InvalidStatus();

        escrow.status = EscrowStatus.Released;
        IERC20(escrow.token).safeTransfer(escrow.recipient, escrow.amount);

        emit PaymentReleased(_escrowId);
    }
}
