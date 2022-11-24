# Rubic Bridge Base
[![NPM Package](https://img.shields.io/npm/v/rubic-bridge-base)](https://www.npmjs.com/package/rubic-bridge-base)

**The package for the development of independent and integrative cross-chain bridges**

Contains basic functionality such as:
* Role Management
* Commission Calculations
* Tracking transaction statuses
* Pause
* Implementation of a basic configuration

## Overview

### Installation

```console
$ npm install rubic-bridge-base
```

### Integration

##### Types of Bridges

There are two options for bridge’s base
1) Only Source Network Functionality - [OnlySourceFunctionality](contracts/architecture/OnlySourceFunctionality.sol)
2) Source and Destination Network Functionality (with Relayers) - [WithDestinationFunctionality](contracts/architecture/WithDestinationFunctionality.sol)

##### Upgradeable/Non-Upgradeable

The package is implemented through OpenZeppelin-Upgradeable, and it can be used for creating Upgradeable bridges.

_Use case for Upgradeable_:

```solidity
import 'rubic-bridge-base/contracts/architecture/OnlySourceFunctionality.sol';

contract RubicBridge is OnlySourceFunctionality{
    
    function initialize(
        uint256 _fixedCryptoFee,
        uint256 _RubicPlatformFee,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts,
        address _admin
        // Additional Parameters...
    ) external initializer { // notice: EXTERNAL
        __OnlySourceFunctionalityInit(
            _fixedCryptoFee,
            _RubicPlatformFee,
            _tokens,
            _minTokenAmounts,
            _maxTokenAmounts,
            _admin
        );
        
        // Additional Logic...
    }
}
```

_Use case for Non-Upgradeable_:

```solidity
import 'rubic-bridge-base/contracts/architecture/OnlySourceFunctionality.sol';

contract SwapBase is OnlySourceFunctionality {
    
    constructor (
        uint256 _fixedCryptoFee,
        uint256 _RubicPlatformFee,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts,
        address _admin
        // Additional Parameters...
    ) {
        initialize(
            _fixedCryptoFee,
            _RubicPlatformFee,
            _tokens,
            _minTokenAmounts,
            _maxTokenAmounts,
            _admin
        );
        
        // Additional Logic...
    }

    function initialize(
        uint256 _fixedCryptoFee,
        uint256 _RubicPlatformFee,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts,
        address _admin
    ) private initializer { // notice: PRIVATE
        __OnlySourceFunctionalityInit(
            _fixedCryptoFee,
            _RubicPlatformFee,
            _tokens,
            _minTokenAmounts,
            _maxTokenAmounts,
            _admin
        );
    }
}
```

When implementing the source swap function using OnlySourceFunctionality, it’s necessary to accrue FixedCryptoFee and TokenFee by using the functions:

```solidity
/**
  * @dev Calculates and accrues fixed crypto fee
  * @param _integrator Integrator's address if there is one
  * @param _info A struct with integrator fee info
  * @return The msg.value without fixedCryptoFee
  */
function accrueFixedCryptoFee(address _integrator, IntegratorFeeInfo memory _info)

/**
  * @dev Calculates token fees and accrues them
  * @param _integrator Integrator's address if there is one
  * @param _info A struct with fee info about integrator
  * @param _amountWithFee Total amount passed by the user
  * @param _token The token in which the fees are collected
  * @param _initBlockchainNum Used if the _calculateFee is overriden by
  * WithDestinationFunctionality, otherwise is ignored
  * @return Amount of tokens without fee
  */
function accrueTokenFees(
     address _integrator,
     IntegratorFeeInfo memory _info,
     uint256 _amountWithFee,
     uint256 _initBlockchainNum,
     address _token
 )
```

### Overview

##### Roles

When the contract is initialized, an arbitrary address (passed into the constructor) is given only the DEFAULT_ADMIN_ROLE role.
If additional roles are needed, they should be added either to the 'initialize' function or to the constructor.
Depending on the Upgradeability.

There are the following roles:
1) DEFAULT_ADMIN_ROLE:
   * Available modifiers: onlyAdmin, onlyManagerAndAdmin
2) MANAGER_ROLE:
   * Available modifiers: onlyManagerAndAdmin

There is also a role in WithDestinationFunctionality contract:
1) RELAYER_ROLE:
   * Available modifiers: onlyRelayer

##### Fees

The basic contract provides the basis for the implementation of various fees, for example, several declared variables and functions.
However, the logic of using these variables and functions must be implemented independently in the inheriting contract.

The database allows to set unique commissions for each integrator of the Rubic protocol, using the following parameters:

* isIntegrator (bool) - true, if integrator is active.
* tokenFee (uint) - fees in tokens payed by a user
* RubicTokenShare (uint) - percentage of tokenFee owned by Rubic <br>
Meaning, RubicFeeAmount = TokenAmount * (tokenFee / 1e6) * (RubicTokenShare / 1e6)
* RubicFixedCryptoShare (uint) - percentage of fixedFeeAmount owned by Rubic
* fixedFeeAmount (uint) - fixed fee amount in a native token 

Parameters are set using the function:

```solidity
function setIntegratorInfo(address _integrator, IntegratorFeeInfo memory _info) external onlyManagerAndAdmin;
```

Integrator's fees are removed using two functions:

**To withdraw commissions in a native token, you must provide a null address**

1) Function for removal on behalf of the integrator

```solidity
function collectIntegratorFee(address _token) external
```

2) Function for withdrawal on behalf of the manager

```solidity
function collectIntegratorFee(address _integrator, address _token) external onlyManagerAndAdmin
```

Fees will still be sent to the integrator's address

When specifying a null address, both tokenFee in the native token and fixedCryptoFee will be removed

_FixedCryptoFee_

FixedCryptoFee is a fixed fee charged on the source network.
It is possible to set a unique FixedCryptoFee for each integrator and a percentage of the fee collected by the Rubic team

When conducting a transaction directly through the Rubic platform, without specifying an integrator, the standard FixedCryptoFee is used

```solidity
// Rubic fixed fee for swap
uint256 public fixedCryptoFee;
// Collected rubic fees in native token
uint256 public collectedCryptoFee;
```

Setting this parameter is possible during initialization through the parameter

```solidity
uint256 _fixedCryptoFee,
```

And through the function

```solidity
function setFixedCryptoFee(uint256 _fixedCryptoFee) external onlyManagerAndAdmin
```

Withdrawal for the Rubiс team is implemented through

```solidity
function collectRubicCryptoFee() external onlyManagerAndAdmin
```

TokenFee

TokenFee - fees collected as a percentage from the amount of tokens.

If an integrator is not specified then the fees are calculated based on the RubicPlatformFee global variable, 
otherwise the corresponding tokenFee to the specified integrator is used. 


##### Events
The functions use the modifier:
```solidity
modifier EventEmitter(BaseCrossChainParams calldata _params, string calldata _providerName) {
```
The first parameter is all the variables for swap and the additional ones for statistics and debug.
```solidity
    struct BaseCrossChainParams {
        address srcInputToken;
        uint256 srcInputAmount;
        uint256 dstChainID;
        address dstOutputToken;
        uint256 dstMinOutputAmount;
        address recipient;
        address integrator;
        address router;
    }
```
The second parameter is a line with information about the provider.
```Solidity
string calldata _providerName
```

Intended format:

```
LiFi:Celer
Rango:Hyphen
Native:Celer
```
Native - native integration.

##### Pauses

The package also provides functions for pausing and resuming the bridge work.
Modifiers should be used with the functions that are to be blocked when paused

```solidity
 function pauseExecution() external onlyManagerAndAdmin { 
     _pause();
 }

 function unpauseExecution() external onlyManagerAndAdmin {
     _unpause();
 }
```

##### Transaction Status

Transaction Statuses are kept in mapping

```solidity
mapping(bytes32 => SwapStatus) public processedTransactions;
```

Use case:

```solidity
processedTransactions[_id] = SwapStatus.Fallback;
```

Implemented Statuses:

```solidity
enum SwapStatus {
     Null,
     Succeeded,
     Failed,
     Fallback
 }
```

There is also a function that replaces the transaction status with an external call

```solidity
function changeTxStatus(
   bytes32 _id, 
   SwapStatus _statusCode
) external onlyRelayer
```

And it is prohibited:
* To set the Null status
* To change status with Success and Fallback


##### Other

_Min Max Amounts_

There is a possibility of limiting the maximum and minimum amounts

While initialization:

```solidity
address[] memory _tokens,
uint256[] memory _minTokenAmounts,
uint256[] memory _maxTokenAmounts,
```

Or through external functions:

```solidity
function setMinTokenAmount(address _token, uint256 _minTokenAmount)
     external
     onlyManagerAndAdmin
 function setMaxTokenAmount(address _token, uint256 _maxTokenAmount)
     external
     onlyManagerAndAdmin
```

_Function for sending tokens_

There is a function for sending native tokens and ERC-20 with the rewriting option

```solidity
function _sendToken(
     address _token,
     uint256 _amount,
     address _receiver
 ) internal virtual
```

_Approves for Routers_

Since an unlimited number of tokens for exchanging can be used on DEX,
each of them must be approved by the router.
That's why the package implements the _smartApprove function, which increases the allowance of a certain token to the maximum if the current allowance is not enough.

```solidity
function smartApprove(
     address _tokenIn,
     uint256 _amount,
     address _to
 )
```
