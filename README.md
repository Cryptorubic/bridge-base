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

### Описание

##### Виды бриджей

Предлагается два варианта основы для бриджей:
1) Для бриджей с единственным транзитным токеном (например, USDT) - [SingleTransitToken](contracts/tokens/SingleTransitToken.sol)
2) Для бриджей с неограниченным количеством транзитных токенов - [MultipleTransitToken](contracts/tokens/MultipleTransitToken.sol)

##### Upgradeable/Non-Upgradeable

Пакет реализован с помощью **OpenZeppelin-Upgradeable**, поэтому его можно использовать для создания Upgradeable бриджей.

_Пример использования для Upgradeable_:

```solidity
import 'rubic-bridge-base/contracts/tokens/MultipleTransitToken.sol';

contract RubicBridge is MultipleTransitToken{
    
    function initialize(
        uint256[] memory _blockchainIDs,
        uint256[] memory _cryptoFees,
        uint256[] memory _platformFees,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts,
        address[] memory _routers
        // Дополнительные параметры...
    ) external initializer { // notice: EXTERNAL
        __MultipleTransitTokenInit(
            _blockchainIDs,
            _cryptoFees,
            _platformFees,
            _tokens,
            _minTokenAmounts,
            _maxTokenAmounts,
            _routers
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
        uint256[] memory _blockchainIDs,
        uint256[] memory _cryptoFees,
        uint256[] memory _platformFees,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts,
        address[] memory _routers
        // Дополнительные параметры...
    ) {
        initialize(
            _blockchainIDs,
            _cryptoFees,
            _platformFees,
            _tokens,
            _minTokenAmounts,
            _maxTokenAmounts,
            _routers
        );
        
        // Дополнительная логика...
    }

    function initialize(
        uint256[] memory _blockchainIDs,
        uint256[] memory _cryptoFees,
        uint256[] memory _platformFees,
        address[] memory _tokens,
        uint256[] memory _minTokenAmounts,
        uint256[] memory _maxTokenAmounts,
        address[] memory _routers
    ) private initializer { // notice: PRIVATE
        __MultipleTransitTokenInit(
            _blockchainIDs,
            _cryptoFees,
            _platformFees,
            _tokens,
            _minTokenAmounts,
            _maxTokenAmounts,
            _routers
        );
    }
}
```

##### Роли

При инициализации контракта деплоеру выдается исключительно роль DEFAULT_ADMIN_ROLE. 
При необходимости наличия дополнительных ролей их следует добавлять, либо в функцию initialize, либо в constructor.
В зависимости от Upgradeability.

Присутствуют следующие роли:
1) DEFAULT_ADMIN_ROLE:
   * view функция для проверки isAdmin()
   * Доступные модификаторы: onlyAdmin, onlyManagerAndAdmin
2) MANAGER_ROLE:
   * view функция для проверки isManager()
   * Доступные модификаторы: onlyManagerAndAdmin, anyRole
3) RELAYER_ROLE:
   * view функция для проверки isRelayer()
   * Доступные модификаторы: onlyRelayer, anyRole
4) VALIDATOR_ROLE:
   * view функция для проверки isValidator()

##### Комиссии

В базовом контракте представлена основа реализации различных комиссий, например некоторые объявленные переменные и функции. 
Однако логику использования этих переменных и функций необходимо реализовывать самостоятельно в наследующем контракте

_CryptoFee_

CryptoFee - это комиссия, собираемая для оплаты работы бекенда. 
Есть возможность собирать разное количество cryptoFee в зависимости от целевого блокчейна.

```solidity
mapping(uint256 => uint256) public blockchainCryptoFee;
```

Маппинг blockchainCryptoFee предполагает, что ключ - айди целевого блокчейна, значение - размер комиссии.

```solidity
uint256[] memory _blockchainIDs,
uint256[] memory _cryptoFees,
```

Есть возможность заполнить его при инициализации контракта

```solidity
setCryptoFeeOfBlockchain(uint256 _blockchainID, uint256 _feeAmount)
```

Так же есть возможность изменять его с помощью **external** функции с модификатором **anyRole**

Снятие Crypto fee осуществляется с помощью функции:

```solidity
function collectCryptoFee(address payable _to) external onlyManagerAndAdmin 
```

_Integrator & Platform fees_

Integrator fee - комиссии, собираемые для интеграторов платформы Rubic через SDK.<br>
Rubic fee - комиссия, собираемая командой Rubic.

Для более гибкой Rubic fee есть возможность указать комиссию в зависимости от исходного (или целевого) блокчейна:

```solidity
mapping(uint256 => uint256) public feeAmountOfBlockchain;
```

Где: ключ - айди блокчейна, значение - размер комиссии.
Предполагается, что данный параметр будет использоваться, если кросс-чейн бридж происходит без участия интегратора.
В ином случае должна изыматься комиссия, указанная для конкретного интегратора:

```solidity
mapping(address => uint256) public integratorFee;
```
Где: ключ - адрес интегратора, значение - размер комиссии.

Так же при взятии Integrator fee, часть этой комиссии начисляется в качестве Rubic fee.
Эта часть указывается с помощью маппинга platformShare.

```solidity
mapping(address => uint256) public platformShare;
```
Где: ключ - адрес интегратора, значение - часть Rubic fee.

Комиссии вычисляются и начисляются с помощью функции calculateFee:
> **calculateFee необходимо вызывать самостоятельно**

Для SingleTransitToken:
```solidity
function calculateFee(
    address integrator,
    uint256 amountWithFee,
    uint256 initBlockchainNum
) internal virtual returns(uint256 amountWithoutFee)
```

Для MultipleTransitToken:

```solidity
function calculateFee(
     address integrator,
     uint256 amountWithFee,
     uint256 initBlockchainNum,
     address token
 ) internal virtual returns(uint256 amountWithoutFee)
```

Где: integrator - адрес интегратора, либо нулевой адрес, amountWithFee - количество средств, из которого вычесть комиссию,
initBlockchainNum - номер исходного блокчейна, token (для MultipleTransitToken) - адрес транзитного токена, 
в котором берется комиссия

calculateFee расчитывает размер комиссии и увеличивает переменные:

для SingleTransitToken:

```solidity
uint256 public availableRubicFee;
mapping(address => uint256) public availableIntegratorFee;
```

для MultipleTransitToken:

```solidity
mapping(address => uint256) public availableRubicFee;
mapping(address => mapping(address => uint256)) public availableIntegratorFee;
```
Где: первый ключ - адрес токена, в котором зачислены комиссии.

**Все комиссии указываются как X, где X/DENOMINATOR = fee** <br>
То есть 1_000_000 = 100%

```solidity
uint256 internal constant DENOMINATOR = 1e6;
```

Комиссии интеграторов и часть команды Рубик можно установить только через external функцию:

```solidity
function setIntegratorFee(
     address _integrator,
     uint256 _fee,
     uint256 _platformShare
 ) external onlyManagerAndAdmin
```

В то время как комиссии Рубика (которые снимаются при отсутствии интегратора) возможно установить
как при инициализации:

```solidity
uint256[] memory _blockchainIDs,
uint256[] memory _platformFees,
```

Так и через external функцию:

```solidity
function setFeeAmountOfBlockchain(
   uint256 _blockchainID,
   uint256 _feeAmount
) external onlyManagerAndAdmin
```

Сбор Rubic fee реализован с помощью функции

Для SingleTransitToken:

```solidity
function collectRubicFee() external onlyManagerAndAdmin
```

Для MultipleTransitToken:

```solidity
function collectRubicFee(address _token) external onlyManagerAndAdmin
```

Сбор Integrator fee реализован с помощью функций:

Для SingleTransitToken:

```solidity
// Интегратор снимает самостоятельно
function collectIntegratorFee() external

// Команда Рубика снимает комиссии за интегратора на его счет
function collectIntegratorFee(address _integrator) external onlyManagerAndAdmin
```

Для MultipleTransitToken:

```solidity
// Интегратор снимает самостоятельно
function collectIntegratorFee(address _token) external

// Команда Рубика снимает комиссии за интегратора на его счет
function collectIntegratorFee(address _token, address _integrator) external onlyManagerAndAdmin
```


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