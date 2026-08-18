# Деплой

Эта инструкция описывает развёртывание системы в EVM-сети.
Перед деплоем ознакомьтесь с [моделью безопасности](security-model.md).

## Подготовка

Требуются:

* RPC выбранной сети;
* аккаунт с нативной валютой для оплаты газа;
* адрес ERC20-токена, используемого как доллар;
* начальная цена токена Фонда;
* имя и символ токена Фонда;
* `contractURI` с метаданными Фонда.

Долларовый токен должен реализовывать `decimals()`
и использовать не более 18 знаков после запятой.

`initialPrice` всегда задаётся с 18 знаками после запятой независимо
от `decimals()` долларового токена. Например, цена `$1` задаётся как `1e18`.

Установите зависимости, соберите контракты и запустите тесты:

```shell
npm ci
npm run build
npm test
```

## Порядок деплоя

### 1. FundToken

Разверните `Token` из `contracts/FundToken.sol`:

```text
Token(name, symbol)
```

Сохраните адрес как `TOKEN`.

### 2. Gate

Разверните `Gate`:

```text
Gate(initialPrice, dollar, TOKEN)
```

где:

* `initialPrice` — начальная цена;
* `dollar` — адрес долларового ERC20;
* `TOKEN` — адрес токена из предыдущего шага.

Сохраните адрес как `GATE`. Передайте владение токеном контракту `Gate`:

```text
Token.transferOwnership(GATE)
```

### 3. PersonalFund

Разверните `Fund` из `contracts/PersonalFund.sol`:

```text
Fund(GATE, contractURI)
```

Сохраните адрес как `FUND`. Передайте владение `Gate` контракту `Fund`:

```text
Gate.transferOwnership(FUND)
```

После этого штатная структура владения должна быть:

```text
Fund owner
    │
    ▼
  Fund
    │ owns
    ▼
  Gate
    │ owns
    ▼
FundToken
```

Если аккаунт, выполнивший деплой `Fund`,
не должен оставаться владельцем Фонда, вызовите:

```text
Fund.transferOwnership(newOwner)
```

а затем с адреса `newOwner`:

```text
Fund.acceptOwnership()
```

## Проверка

После деплоя проверьте:

```text
Fund.owner()            == ожидаемый owner
Fund.gate()             == GATE

Gate.owner()            == FUND
Gate.fundToken()        == TOKEN
Gate.dollar()           == dollar
Gate.entryPrice()       == initialPrice
Gate.currentStageId()   == 1

Token.owner()           == GATE
Token.totalSupply()     == 0
```
