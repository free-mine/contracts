# Деплой

Эта инструкция описывает развёртывание контрактов Free Mine.

## Подготовка

Для деплоя нужны:

* RPC выбранной EVM-сети;
* аккаунт с нативной валютой для газа;
* адрес долларового ERC20-токена;
* начальная цена Magic Ore;
* имя и символ Magic Ore;
* `contractURI` для `OreVein`.

Долларовый токен должен реализовывать `decimals()`.
Число знаков после запятой должно быть не больше 18.
`initialPrice` всегда имеет 18 знаков после запятой.
Например, цена в один доллар задаётся как `1e18`.
Установите зависимости и соберите контракты:

```sh
npm ci
npm run build
```

В репозитории нет отдельной команды для деплоя.
Ниже указан порядок вызовов.

## 1. MagicOre

Разверните `MagicOre`:

```solidity
MagicOre(name, symbol)
```

Сохраните адрес контракта как `MAGIC_ORE`.
После деплоя владельцем `MagicOre` является деплоер.

## 2. FreeMine

Разверните `FreeMine`:

```solidity
FreeMine(initialPrice, dollar, MAGIC_ORE)
```

Параметры:

* `initialPrice` — начальная цена Magic Ore;
* `dollar` — адрес долларового ERC20-токена;
* `MAGIC_ORE` — адрес `MagicOre`.

Сохраните адрес контракта как `FREE_MINE`.
Передайте владение `MagicOre` контракту `FreeMine`:

```solidity
MagicOre.transferOwnership(FREE_MINE)
```

После этого владельцем `MagicOre` должен быть `FreeMine`.

## 3. OreVein

Разверните `OreVein`:

```solidity
OreVein(FREE_MINE, contractURI)
```

Параметры:

* `FREE_MINE` — адрес `FreeMine`;
* `contractURI` — строка с метаданными контракта.

Сохраните адрес контракта как `ORE_VEIN`.
После деплоя владельцем `OreVein` является деплоер.
Передайте владение `FreeMine` контракту `OreVein`:

```solidity
FreeMine.transferOwnership(ORE_VEIN)
```

После этого владельцем `FreeMine` должен быть `OreVein`.

## Проверка

Проверьте `OreVein`:

```solidity
OreVein.owner() == deployer
OreVein.freeMine() == FREE_MINE
OreVein.contractURI() == contractURI
```

Проверьте `FreeMine`:

```solidity
FreeMine.owner() == ORE_VEIN
FreeMine.magicOre() == MAGIC_ORE
FreeMine.dollar() == dollar
FreeMine.entryPrice() == initialPrice
FreeMine.currentShiftId() == 1
```

Проверьте `MagicOre`:

```solidity
MagicOre.owner() == FREE_MINE
MagicOre.totalSupply() == 0
```
