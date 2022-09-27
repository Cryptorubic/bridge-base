# Rubic Bridge Base
[![NPM Package](https://img.shields.io/npm/v/rubic-bridge-base)](https://www.npmjs.com/package/rubic-bridge-base)

**Пакет для разработки самостоятельных и интеграционных кросс-чейн бриджей**

Содержит базовый функционал, такой как:
* Управление ролями
* Расчеты комиссий
* Трекинг статусов транзакций
* Пауза
* Реализация базовой конфигурации

## Обзор

### Установка

```console
$ npm install rubic-bridge-base
```

### Интеграция

##### Виды бриджей

Предлагается два варианта основы для бриджей:
1) С функционалом только в исходной сети - [OnlySourceFunctionality](contracts/architecture/OnlySourceFunctionality.sol)
2) С функционалом в исходной и целевой сетях (с релеерами) - [WithDestinationFunctionality](contracts/architecture/WithDestinationFunctionality.sol)

##### Upgradeable/Non-Upgradeable

Пакет реализован с помощью **OpenZeppelin-Upgradeable**, поэтому его можно использовать для создания Upgradeable бриджей.

_Пример использования для Upgradeable_:

```solidity
import 'rubic-bridge-base/contracts/architecture/OnlySourceFunctionality.sol';

contract RubicBridge is OnlySourceFunctionality{
    
    function initialize(
        uint256 _fixedCryptoFee,
        address[] memory _routers,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts,
        uint256 _RubicPlatformFee
        // Дополнительные параметры...
    ) external initializer { // notice: EXTERNAL
        __OnlySourceFunctionalityInit(
            _fixedCryptoFee,
            _routers,
            _tokens,
            _minTokenAmounts,
            _maxTokenAmounts,
            _RubicPlatformFee
        );
        
        // Дополнительная логика...
    }
}
```

_Пример использования для Non-Upgradeable_:

```solidity
import 'rubic-bridge-base/contracts/tokens/MultipleTransitToken.sol';

contract SwapBase is MultipleTransitToken {
    
    constructor (
        uint256 _fixedCryptoFee,
        address[] memory _routers,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts,
        uint256 _RubicPlatformFee
        // Дополнительные параметры...
    ) {
        initialize(
            _fixedCryptoFee,
            _routers,
            _tokens,
            _minTokenAmounts,
            _maxTokenAmounts,
            _RubicPlatformFee
        );
        
        // Дополнительная логика...
    }

    function initialize(
        uint256 _fixedCryptoFee,
        address[] memory _routers,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts,
        uint256 _RubicPlatformFee
    ) private initializer { // notice: PRIVATE
        __OnlySourceFunctionalityInit(
            _fixedCryptoFee,
            _routers,
            _tokens,
            _minTokenAmounts,
            _maxTokenAmounts,
            _RubicPlatformFee
        );
    }
}
```

При реализации функции исходного свапа с использованием OnlySourceFunctionality необходимо снять FixedCryptoFee и TokenFee это делается с помощью функций:

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

### Описание

##### Роли

При инициализации контракта деплоеру выдается исключительно роль DEFAULT_ADMIN_ROLE. 
При необходимости наличия дополнительных ролей их следует добавлять, либо в функцию initialize, либо в constructor.
В зависимости от Upgradeability.

Присутствуют следующие роли:
1) DEFAULT_ADMIN_ROLE:
   * Доступные модификаторы: onlyAdmin, onlyManagerAndAdmin
2) MANAGER_ROLE:
   * Доступные модификаторы: onlyManagerAndAdmin

В контракте WithDestinationFunctionality также присутствует роль:
1) RELAYER_ROLE:
   * Доступные модификаторы: onlyRelayer

##### Комиссии

В базовом контракте представлена основа реализации различных комиссий, например, несколько объявленных переменных и функции. 
Однако логику использования этих переменных и функций необходимо реализовывать самостоятельно в наследующем контракте

База позволяет выставить уникальные комиссии каждому интегратору протокола Rubic. А именно с помощью следующих параметров:

* isIntegrator (bool) - true, если интегратор активный.
* tokenFee (uint) - комиссия в токенах, оплачиваемая юзером
* RubicTokenShare (uint) - процент от tokenFee, принадлежащий Rubic <br>
То есть RubicFeeAmount = TokenAmount * (tokenFee / 1e6) * (RubicTokenShare / 1e6)
* RubicFixedCryptoShare (uint) - процент от fixedFeeAmount, принадлежащий Rubic
* fixedFeeAmount (uint) - комиссия в нативном токене фиксированного размера

Параметры выставляются с помощью функции:

```solidity
function setIntegratorInfo(address _integrator, IntegratorFeeInfo memory _info) external onlyManagerAndAdmin;
```

Комиссии интегратора снимаются с помощью двух функций:

**Для снятия комиссий в нативном токене необходимо указать нулевой адрес**

1) Функция для снятия от лица интегратора

```solidity
function collectIntegratorFee(address _token) external
```

2) Функция для снятия от лица менеджера

```solidity
function collectIntegratorFee(address _integrator, address _token) external onlyManagerAndAdmin
```

Комиссии всё равно будут направлены на адрес интегратора

При указании нулевого адреса будут сняты как и tokenFee в нативном токене, так и fixedCryptoFee

_FixedCryptoFee_

FixedCryptoFee - это комиссия фиксированного размера, снимаемая в исходной сети. 
Есть возможность выставить уникальную FixedCryptoFee для каждого интегратора и процент от этой комиссии, собираемый командой Rubic

При проведении транзакции напрямую через платформу Rubic, то есть без указания интегратора, используется стандартная FixedCryptoFee

```solidity
// Rubic fixed fee for swap
uint256 public fixedCryptoFee;
// Collected rubic fees in native token
uint256 public collectedCryptoFee;
```

Установка данного параметра возможна во время инициализации через параметр

```solidity
uint256 _fixedCryptoFee,
```

А так же с помощью функции

```solidity
function setFixedCryptoFee(uint256 _fixedCryptoFee) external onlyManagerAndAdmin
```

Снятие для команды Rubic происходит через 

```solidity
function collectRubicCryptoFee() external onlyManagerAndAdmin
```

TokenFee

TokenFee - комиссия в процентах собираемая от количества токенов.

Если интегратор указан, то использоуется соответствующая ему TokenFee, иначе:

1) При использовании OnlySourceFunctionality:
```solidity
uint256 public RubicPlatformFee;
```
2) При использовании WithDestinationFunctionality:

Для более гибкой Rubic fee есть возможность указать комиссию в зависимости от исходного блокчейна если используется WithDestinationFunctionality:
```solidity
mapping(uint256 => uint256) public blockchainToRubicPlatformFee;
```

##### Ивенты
В функциях используется модификатор:
```solidity
modifier eventEmitter(BaseCrossChainParams calldata _params, string calldata _providerName) {
```
Первый параметр - все переменные для свапа, а также дполонительные для статистики, дебага.
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
Второй параметр - строка с информацией о провайдере.
```Solidity
string calldata _providerName
```

Предполагаемый формат:

```
LiFi:Celer
Rango:Hyphen
Native:Celer
```
Native - нативная интеграция.

##### Паузы

В пакете также представлены функции для паузы и анпаузы работы бриджа.
Модификаторы необходимо использовать на те фукнции, которые должны быть заблокированы при паузе

```solidity
 function pauseExecution() external onlyManagerAndAdmin { 
     _pause();
 }

 function unpauseExecution() external onlyManagerAndAdmin {
     _unpause();
 }
```

##### Статусы транзакций

Статусы транзакций хранятся в маппинге

```solidity
mapping(bytes32 => SwapStatus) public processedTransactions;
```

Пример использования:

```solidity
processedTransactions[_id] = SwapStatus.Fallback;
```

Реализованные статусы:

```solidity
enum SwapStatus {
     Null,
     Succeeded,
     Failed,
     Fallback
 }
```

Также имеется функция для замены статуса транзакции с помощью external вызова

```solidity
function changeTxStatus(
   bytes32 _id, 
   SwapStatus _statusCode
) external onlyRelayer
```

При этом запрещается:
* Устанавливать статус Null
* Изменять статус с Success и Fallback

##### Разрешенные роутеры

Для возможности создания бриджей со свапами на различных DEX представлена
основа для реализации логики поддерживаемых DEXов

```solidity
EnumerableSetUpgradeable.AddressSet internal availableRouters;
```

Пример использования:

```solidity
if (!availableRouters.contains(dex)) {
   return false;
}
```

Также для удобного просмотра поддерживаемых роутеров существует view external функция

```solidity
function getAvailableRouters() external view returns(address[] memory)
```

Для добавления роутера подразумевается использование следующей функции:

```solidity
function addAvailableRouter(address _router) external onlyManagerAndAdmin
```

Также роутеры можно добавить во время инициализации

```solidity
address[] memory _routers
```

##### Остальное

_Min Max Amounts_

Представлена возможность ограничения максимальных и минимальных сумм

Для SingleTransitToken:

Во время инициализации:

```solidity
uint256 _minTokenAmount,
uint256 _maxTokenAmount,
```

Или же через external функции:

```solidity
function setMinTokenAmount(uint256 _minTokenAmount)
function setMaxTokenAmount(uint256 _maxTokenAmount)
```

Для MultipleTransitToken:

Во время инициализации:

```solidity
address[] memory _tokens,
uint256[] memory _minTokenAmounts,
uint256[] memory _maxTokenAmounts,
```

Или через external функции:

```solidity
function setMinTokenAmount(address _token, uint256 _minTokenAmount)
     external
     onlyManagerAndAdmin
 function setMaxTokenAmount(address _token, uint256 _maxTokenAmount)
     external
     onlyManagerAndAdmin
```

_Функция для отправки токенов_

Представлена функция для отправки нативных токенов и ERC-20 с возможностью перезаписи

```solidity
function _sendToken(
     address _token,
     uint256 _amount,
     address _receiver
 ) internal virtual
```

_Апрувы на роутеры_

Поскольку может использоваться неограниченное количество токенов для обменов на DEX,
каждый из них необходимо апрувать на роутер.
Для этого в пакете реализована функция _smartApprove, которая увеличивает аллованс
определенного токена на максимум, если текущего аллованса не хватает.

```solidity
function smartApprove(
     address _tokenIn,
     uint256 _amount,
     address _to
 )
```
