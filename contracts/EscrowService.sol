// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title EscrowService
 * @dev A decentralized escrow service for secure peer-to-peer transactions
 * @author EscrowService Team
 */
contract Project {
    
    // Escrow states
    enum EscrowState { 
        AWAITING_PAYMENT, 
        AWAITING_DELIVERY, 
        COMPLETE, 
        DISPUTED,
        REFUNDED 
    }
    
    // Escrow structure
    struct Escrow {
        address payable buyer;
        address payable seller;
        address payable arbiter;
        uint256 amount;
        EscrowState state;
        bool buyerApproved;
        bool sellerApproved;
        uint256 createdAt;
        string description;
    }
    
    // State variables
    mapping(uint256 => Escrow) public escrows;
    uint256 public escrowCounter;
    uint256 public constant ARBITER_FEE_PERCENT = 2; // 2% fee for arbiter
    
    // Events
    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed buyer,
        address indexed seller,
        address arbiter,
        uint256 amount,
        string description
    );
    
    event PaymentDeposited(uint256 indexed escrowId, uint256 amount);
    event DeliveryConfirmed(uint256 indexed escrowId);
    event EscrowCompleted(uint256 indexed escrowId);
    event EscrowDisputed(uint256 indexed escrowId);
    event EscrowRefunded(uint256 indexed escrowId);
    
    // Modifiers
    modifier onlyBuyer(uint256 _escrowId) {
        require(msg.sender == escrows[_escrowId].buyer, "Only buyer can call this");
        _;
    }
    
    modifier onlySeller(uint256 _escrowId) {
        require(msg.sender == escrows[_escrowId].seller, "Only seller can call this");
        _;
    }
    
    modifier onlyArbiter(uint256 _escrowId) {
        require(msg.sender == escrows[_escrowId].arbiter, "Only arbiter can call this");
        _;
    }
    
    modifier inState(uint256 _escrowId, EscrowState _state) {
        require(escrows[_escrowId].state == _state, "Invalid escrow state");
        _;
    }
    
    /**
     * @dev Creates a new escrow agreement
     * @param _seller Address of the seller
     * @param _arbiter Address of the arbiter (dispute resolver)
     * @param _description Description of the goods/services
     * @return escrowId The ID of the created escrow
     */
    function createEscrow(
        address payable _seller,
        address payable _arbiter,
        string memory _description
    ) external payable returns (uint256 escrowId) {
        require(msg.value > 0, "Escrow amount must be greater than 0");
        require(_seller != address(0), "Invalid seller address");
        require(_arbiter != address(0), "Invalid arbiter address");
        require(_seller != msg.sender, "Seller cannot be the buyer");
        require(_arbiter != msg.sender && _arbiter != _seller, "Arbiter must be independent");
        
        escrowId = escrowCounter++;
        
        escrows[escrowId] = Escrow({
            buyer: payable(msg.sender),
            seller: _seller,
            arbiter: _arbiter,
            amount: msg.value,
            state: EscrowState.AWAITING_DELIVERY,
            buyerApproved: false,
            sellerApproved: false,
            createdAt: block.timestamp,
            description: _description
        });
        
        emit EscrowCreated(escrowId, msg.sender, _seller, _arbiter, msg.value, _description);
        emit PaymentDeposited(escrowId, msg.value);
        
        return escrowId;
    }
    
    /**
     * @dev Confirms delivery and approves payment release
     * @param _escrowId The ID of the escrow
     */
    function confirmDelivery(uint256 _escrowId) 
        external 
        onlyBuyer(_escrowId) 
        inState(_escrowId, EscrowState.AWAITING_DELIVERY) 
    {
        escrows[_escrowId].buyerApproved = true;
        
        emit DeliveryConfirmed(_escrowId);
        
        // If both parties approve, complete the escrow
        if (escrows[_escrowId].sellerApproved) {
            _completeEscrow(_escrowId);
        }
    }
    
    /**
     * @dev Seller confirms they are ready to receive payment
     * @param _escrowId The ID of the escrow
     */
    function confirmReadyForPayment(uint256 _escrowId) 
        external 
        onlySeller(_escrowId) 
        inState(_escrowId, EscrowState.AWAITING_DELIVERY) 
    {
        escrows[_escrowId].sellerApproved = true;
        
        // If both parties approve, complete the escrow
        if (escrows[_escrowId].buyerApproved) {
            _completeEscrow(_escrowId);
        }
    }
    
    /**
     * @dev Resolves a dispute (only callable by arbiter)
     * @param _escrowId The ID of the escrow
     * @param _releaseToBuyer True to refund buyer, false to pay seller
     */
    function resolveDispute(uint256 _escrowId, bool _releaseToBuyer) 
        external 
        onlyArbiter(_escrowId) 
        inState(_escrowId, EscrowState.DISPUTED) 
    {
        Escrow storage escrow = escrows[_escrowId];
        uint256 arbiterFee = (escrow.amount * ARBITER_FEE_PERCENT) / 100;
        uint256 remainingAmount = escrow.amount - arbiterFee;
        
        // Pay arbiter fee
        escrow.arbiter.transfer(arbiterFee);
        
        if (_releaseToBuyer) {
            escrow.buyer.transfer(remainingAmount);
            escrow.state = EscrowState.REFUNDED;
            emit EscrowRefunded(_escrowId);
        } else {
            escrow.seller.transfer(remainingAmount);
            escrow.state = EscrowState.COMPLETE;
            emit EscrowCompleted(_escrowId);
        }
    }
    
    /**
     * @dev Raises a dispute (callable by buyer or seller)
     * @param _escrowId The ID of the escrow
     */
    function raiseDispute(uint256 _escrowId) external {
        require(
            msg.sender == escrows[_escrowId].buyer || msg.sender == escrows[_escrowId].seller,
            "Only buyer or seller can raise dispute"
        );
        require(
            escrows[_escrowId].state == EscrowState.AWAITING_DELIVERY,
            "Can only dispute active escrows"
        );
        
        escrows[_escrowId].state = EscrowState.DISPUTED;
        emit EscrowDisputed(_escrowId);
    }
    
    /**
     * @dev Internal function to complete escrow
     * @param _escrowId The ID of the escrow
     */
    function _completeEscrow(uint256 _escrowId) internal {
        Escrow storage escrow = escrows[_escrowId];
        escrow.state = EscrowState.COMPLETE;
        
        // Transfer payment to seller
        escrow.seller.transfer(escrow.amount);
        
        emit EscrowCompleted(_escrowId);
    }
    
 
    function getEscrow(uint256 _escrowId) external view returns (
        address buyer,
        address seller,
        address arbiter,
        uint256 amount,
        EscrowState state,
        bool buyerApproved,
        bool sellerApproved,
        uint256 createdAt,
        string memory description
    ) {
        Escrow storage escrow = escrows[_escrowId];
        return (
            escrow.buyer,
            escrow.seller,
            escrow.arbiter,
            escrow.amount,
            escrow.state,
            escrow.buyerApproved,
            escrow.sellerApproved,
            escrow.createdAt,
            escrow.description
        );
    }
    
    /**
     * @dev Emergency function to get contract balance (for debugging)
     * @return The contract's current balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
