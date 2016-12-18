pragma solidity ^0.4.6;

contract DXF_Tokens{

  //States
  bool public doOpen=true;
  bool public refundState;
  bool public transferLocked=true;

  uint256 public startingDateFunding;
  uint256 public closingDateFunding;
  //Maximum number of participants
  uint256 public maxNumberMembers=6250;
  //Token caps, this includes the 12500 tokens already created for previous DO
  uint256 public totalTokens;
  uint256 public constant tokensCreationMin = 25000 ether;
  uint256 public constant tokensCreationCap = 75000 ether;
  //Cap of 12500 ethers worth of tokens to be distributed 
  //to previous DO members in exchange for their rouleth accounts
  uint256 public remainingTokensVIPs=12500 ether;
  uint256 public constant tokensCreationVIPsCap = 12500 ether; 


  mapping (address => uint256) balances;
  mapping (address => bool) vips;
  mapping (address => uint256) indexMembers;
  
  struct Member
  {
    address member;
    uint timestamp;
    uint initial_value;
  }
  Member[] public members;

  event Transfer(address indexed _from, address indexed _to, uint256 _value);
  event Refund(address indexed _to, uint256 _value);
  event VipMigration(address indexed _vip, uint256 _value);

  // Token parameters
  string public constant name = "DXF - Decentralized eXperience FriendsClub";
  string public constant symbol = "DXF";
  uint8 public constant decimals = 18;  // 18 decimal places, the same as ETH.

  address public admin;
  address public multisigDXF;

  modifier onlyAdmin()
  {
    if (msg.sender!=admin) throw;
    _;
  }

  function DXF_Tokens()
  {
    admin = msg.sender;
    startingDateFunding=now;
    multisigDXF="ADDRESS_TO_FILL"; //or switch to constructor param
    //increment array by 1 for indexes
    members.push(Member(0,0,0));
  }


  //empty fallback
  function ()
    {
      throw;
    }

  //USER FUNCTIONS  
  /// @notice Create tokens when funding is active.
  /// @notice By using this function you accept the terms of DXDO
  /// @dev Required state: Funding Active
  /// @dev State transition: -> Funding Success (only if cap reached)
  function acceptTermsAndJoinDXF() payable external 
  {
    // refuse if more than 6 months have passed
    if (now>startingDateFunding+200 days) throw;
    // Abort if DO is not open.
    if (!doOpen) throw;
    // verify if the account is not a VIP account
    if (vips[msg.sender]) throw;
    // Do not allow creating less than 10 ether or more than the cap tokens.
    if (msg.value < 10 ether) throw;
    if (msg.value > (tokensCreationCap - totalTokens)) throw;
    // Enforce cap of 2500 ether per address / individual (cf. terms)
    //    if (msg.value > (2500 ether - balances[msg.sender])) throw;
    // Register member
    if (balances[msg.sender]==0)
      {
	indexMembers[msg.sender]=members.length;
	members.push(Member(msg.sender,now,msg.value));
      }
    else
      {
	members[indexMembers[msg.sender]].initial_value+=msg.value;
      }
    if (members.length>maxNumberMembers) throw;
    //Send the funds to the MultiSig
    if (multisigDXF==0) throw;
    multisigDXF.send(msg.value);
    // Assign new tokens to the sender
    uint numTokens = msg.value;
    totalTokens += numTokens;
    // Do not allow creating tokens if we don't leave enough for the VIPs
    if ( (tokensCreationCap-totalTokens) < remainingTokensVIPs ) throw;
    balances[msg.sender] += numTokens;
    // Log token creation event
    Transfer(0, msg.sender, numTokens);
  }



  //NOT INCLUDED IN LATEST VERSION
  /* /// @notice Get back the ether sent during the funding in case the funding */
  /* /// has not reached the minimum level. */
  /* /// @dev Required state: refund true */
  /* function refund() */
  /* { */
  /*   // Abort if not in refund state */
  /*   if (!refundState) throw; */
  /*   // Not refunded for VIP, we will do a manual refund for them */
  /*   // via the payback function */
  /*   if (vips[msg.sender]) throw; */
  /*   uint value = balances[msg.sender]; */
  /*   if (value == 0) throw; */
  /*   balances[msg.sender] = 0; */
  /*   totalTokens -= value; */
  /*   delete members[indexMembers[msg.sender]]; */
  /*   indexMembers[msg.sender]=0; */
  /*   Refund(msg.sender, value); */
  /*   if (!msg.sender.send(value)) throw; */
  /* } */


  //@notice Full Tranfer of DX tokens from sender to '_to'
  //@dev only active if tranfer has been unlocked
  //@param _to address of recipient
  //@param _value amount to tranfer
  //@return success of tranfer ?
  function fullTransfer(address _to) returns (bool)
  {
    // Cancel if tranfer is not allowed
    if (transferLocked) throw;
    if (refundState) throw;
    if (balances[_to]!=0) throw;
    if (balances[msg.sender]!=0)
      {
	uint senderBalance = balances[msg.sender];
	balances[msg.sender] = 0;
	balances[_to]=senderBalance;
	if (vips[msg.sender])
	  {
	    vips[_to]=true;
	    vips[msg.sender]=false;
	  }
	members[indexMembers[msg.sender]].member=_to;
	indexMembers[_to]=indexMembers[msg.sender];
	indexMembers[msg.sender]=0;
	Transfer(msg.sender, _to, senderBalance);
	return true;
      }
    else
      {
	return false;
      }
  }


  //ADMIN FUNCTIONS


  //@notice called by Admin to manually register migration of previous DO
  //@dev can not be called with a _vip address that is already investor
  //@dev can be called even after the DO is sealed
  //@dev since it uses the tokens already attributed to admin
  //@param _value : balance of VIP at DXDO's creation date
  function registerVIP(address _vip, address _vip_confirm, uint256 _previous_balance)
    onlyAdmin
  {
    if (_vip==0) throw;
    if (_vip!=_vip_confirm) throw;
    //don't allow migration to a non empty address
    if (balances[_vip]!=0) throw; 
    if (_previous_balance==0) throw;
    //too many tokens created via VIP migration
    uint numberTokens=_previous_balance+(_previous_balance/3);
    totalTokens+=numberTokens;
    if (numberTokens>remainingTokensVIPs) throw;     
    remainingTokensVIPs-=numberTokens;
    balances[_vip]+=numberTokens;
    indexMembers[_vip]=members.length;
    members.push(Member(_vip,now,_previous_balance));
    vips[_vip]=true;
    VipMigration(_vip,_previous_balance);
  }


  /// @notice Pay back the ether contributed to the DAO
  function paybackContribution(uint i)
    payable
    onlyAdmin
  {
    // Abort if DO is open.
    // if (doOpen) throw;
    address memberRefunded=members[i].member;
    if (memberRefunded==0) throw;
    uint amountTokens=msg.value;
    if (vips[memberRefunded]) 
      {
	amountTokens+=amountTokens/3;
	remainingTokensVIPs+=amountTokens;
      }
    if (amountTokens>balances[memberRefunded]) throw;
    balances[memberRefunded]-=amountTokens;
    totalTokens-=amountTokens;
    if (balances[memberRefunded]==0) 
      {
	delete members[i];
	vips[memberRefunded]=false;
	indexMembers[memberRefunded]=0;
      }
    if (!memberRefunded.send(msg.value)) throw;
    Refund(memberRefunded,msg.value);
  }


  function changeAdmin(address _admin, address _admin_confirm)
    onlyAdmin
  {
    if (_admin!=_admin_confirm) throw;
    if (_admin==0) throw;
    admin=_admin;
  }

  //@notice called to seal the DO
  //@dev can not be opened again, marks the end of the fundraising 
  //and the recruitment in the DO
  function closeFunding()
    onlyAdmin
  {
    closingDateFunding=now;
    doOpen=false;
    //verify if the cap has been reached
    //if not : refund mode
    if (totalTokens<tokensCreationMin)
      {
	refundState=true;
      }
    else
      {
	if(!admin.send(this.balance)) throw;
      }
  }

  //NOT INCLUDED
  /* function reopenDO() */
  /*   onlyAdmin */
  /* { */
  /*   doOpen=true; */
  /*   transferLocked=true; */
  /* } */

  function allowTransfers()
    onlyAdmin
  {
    if (doOpen) throw;
    transferLocked=false;
  }

  function disableTransfers()
    onlyAdmin
  {
    if (doOpen) throw;
    transferLocked=true;
  }


  //Constant Functions
  function totalSupply() external constant returns (uint256) 
  {
    return totalTokens;
  }

  function balanceOf(address _owner) external constant returns (uint256) 
  {
    return balances[_owner];
  }

  function accountInformation(address _owner) external constant returns (bool vip, uint balance_ether, uint share_dxf) 
  {
    vip=vips[_owner];
    balance_ether=balances[_owner]/(1 ether);
    share_dxf=100*balances[_owner]/totalTokens;
  }


}
