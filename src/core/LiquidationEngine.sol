// LATER

// This is the contract that Chainlink Automation or another off-chain bot pings to:

// Check if a position’s health factor is below threshold.

// If so, call:

// PositionManager.liquidatePosition(positionId) → which:

// Closes the position

// Sends collateral to insurance/liquidator

// Burns or marks NFT as closed