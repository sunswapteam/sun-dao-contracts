interface LiquidityGauge:
    # Presumably, other gauges will provide the same interfaces
    def integrate_fraction(addr: address) -> uint256: view
    def user_checkpoint(addr: address) -> bool: nonpayable

interface VAULT:
    def mint(_to: address, _value: uint256): nonpayable

interface GaugeController:
    def gauge_types(addr: address) -> int128: view


event Minted:
    recipient: indexed(address)
    gauge: address
    minted: uint256


vault: public(address)

REDUCER: constant(uint256) = 1461501637330902918203684832716283019655932542975  #0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff


# user -> gauge -> value
minted: public(HashMap[address, HashMap[address, uint256]])

# minter -> user -> can mint?
allowed_to_mint_for: public(HashMap[address, HashMap[address, bool]])
able_to_mint: public(HashMap[address, bool])

admin: public(address)  # Can be a smart contract
future_admin: public(address)  # Can be a smart contract


event CommitOwnership:
    admin: address

event ApplyOwnership:
    admin: address

initialed: public(bool)


@internal
@view
def convert_to_addr(src: bytes32) -> address:
    # convert bytes32 to addr,reduce 0x41
    return convert(bitwise_and(REDUCER, convert(src, uint256)),address)



@external
def initial(_vault: address, _admin: address):
    assert self.initialed == False

    self.initialed = True
    self.vault = _vault
    self.admin = _admin


@external
def set_able_to_mint(_addr: bytes32, _ok: bool):
    assert msg.sender == self.admin  # dev: admin only
    addr: address = self.convert_to_addr(_addr)
    self.able_to_mint[addr] = _ok


@external
def commit_transfer_ownership(_addr: bytes32):
    """
    @notice Transfer ownership of VotingEscrow contract to `addr`
    @param addr Address to have ownership transferred to
    """
    addr: address = self.convert_to_addr(_addr)

    assert msg.sender == self.admin  # dev: admin only
    self.future_admin = addr
    log CommitOwnership(addr)


@external
def apply_transfer_ownership():
    """
    @notice Apply ownership transfer
    """
    assert msg.sender == self.admin  # dev: admin only
    _admin: address = self.future_admin
    assert _admin != ZERO_ADDRESS  # dev: admin not set
    self.admin = _admin
    log ApplyOwnership(_admin)


@internal
def _mint_for(gauge_addr: address, _for: address):
    #assert GaugeController(self.controller).gauge_types(gauge_addr) >= 0  # dev: gauge is not added
    assert self.able_to_mint[gauge_addr]

    LiquidityGauge(gauge_addr).user_checkpoint(_for)
    total_mint: uint256 = LiquidityGauge(gauge_addr).integrate_fraction(_for)
    to_mint: uint256 = total_mint - self.minted[_for][gauge_addr]

    if to_mint != 0:
        VAULT(self.vault).mint(_for, to_mint)
        self.minted[_for][gauge_addr] = total_mint

        log Minted(_for, gauge_addr, total_mint)



@external
@nonreentrant('lock')
def claim(gauge_addr: bytes32):
    """
    @notice Mint everything which belongs to `msg.sender` and send to them
    @param gauge_addr `LiquidityGauge` address to get mintable amount from
    """
    self._mint_for(self.convert_to_addr(gauge_addr), msg.sender)



@external
@nonreentrant('lock')
def mint(gauge_addr: bytes32):
    """
    @notice Mint everything which belongs to `msg.sender` and send to them
    @param gauge_addr `LiquidityGauge` address to get mintable amount from
    """
    self._mint_for(self.convert_to_addr(gauge_addr), msg.sender)


@external
@nonreentrant('lock')
def mint_many(gauge_addrs: bytes32[8]):
    """
    @notice Mint everything which belongs to `msg.sender` across multiple gauges
    @param gauge_addrs List of `LiquidityGauge` addresses
    """
    for i in range(8):
        addr: address = self.convert_to_addr(gauge_addrs[i])

        if addr == ZERO_ADDRESS:
            break
        self._mint_for(addr, msg.sender)


@external
@nonreentrant('lock')
def mint_for(_gauge_addr: bytes32, _forwhom: bytes32):
    """
    @notice Mint tokens for `_for`
    @dev Only possible when `msg.sender` has been approved via `toggle_approve_mint`
    @param gauge_addr `LiquidityGauge` address to get mintable amount from
    @param _for Address to mint to
    """
    gauge_addr: address = self.convert_to_addr(_gauge_addr)
    _for: address = self.convert_to_addr(_forwhom)

    if self.allowed_to_mint_for[msg.sender][_for]:
        self._mint_for(gauge_addr, _for)


@external
def toggle_approve_mint(_minting_user: bytes32):
    """
    @notice allow `minting_user` to mint for `msg.sender`
    @param minting_user Address to toggle permission for
    """
    minting_user: address = self.convert_to_addr(_minting_user)

    self.allowed_to_mint_for[minting_user][msg.sender] = not self.allowed_to_mint_for[minting_user][msg.sender]