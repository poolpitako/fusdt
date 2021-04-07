from brownie import Contract, Wei
import pytest


def test_shutdown(gov, bob, token, vault, strategy, strategist, token_whale):
    token.transfer(bob, 1_000 * 1e6, {"from": token_whale})
    token.approve(vault, 2**256-1, {"from": bob})
    vault.deposit({"from": bob})

    strategy.harvest({"from": strategist})
