---
id: interfaces_IStakingAuRa
title: IStakingAuRa
---

<div class="contract-doc"><div class="contract"><h2 class="contract-header"><span class="contract-kind">interface</span> IStakingAuRa</h2><div class="source">Source: <a href="https://github.com/poanetwork/posdao-contracts/blob/v0.1.0/contracts/interfaces/IStakingAuRa.sol" target="_blank">contracts/interfaces/IStakingAuRa.sol</a></div></div><div class="index"><h2>Index</h2><ul><li><a href="interfaces_IStakingAuRa.html#initialize">initialize</a></li><li><a href="interfaces_IStakingAuRa.html#setStakingEpochStartBlock">setStakingEpochStartBlock</a></li><li><a href="interfaces_IStakingAuRa.html#stakeWithdrawDisallowPeriod">stakeWithdrawDisallowPeriod</a></li><li><a href="interfaces_IStakingAuRa.html#stakingEpochDuration">stakingEpochDuration</a></li><li><a href="interfaces_IStakingAuRa.html#stakingEpochEndBlock">stakingEpochEndBlock</a></li></ul></div><div class="reference"><h2>Reference</h2><div class="functions"><h3>Functions</h3><ul><li><div class="item function"><span id="initialize" class="anchor-marker"></span><h4 class="name">initialize</h4><div class="body"><code class="signature"><span>abstract </span>function <strong>initialize</strong><span>(address , address , address[] , uint256 , uint256 , uint256 , uint256 ) </span><span>external </span></code><hr/><dl><dt><span class="label-parameters">Parameters:</span></dt><dd><div><code></code> - address</div><div><code></code> - address</div><div><code></code> - address[]</div><div><code></code> - uint256</div><div><code></code> - uint256</div><div><code></code> - uint256</div><div><code></code> - uint256</div></dd></dl></div></div></li><li><div class="item function"><span id="setStakingEpochStartBlock" class="anchor-marker"></span><h4 class="name">setStakingEpochStartBlock</h4><div class="body"><code class="signature"><span>abstract </span>function <strong>setStakingEpochStartBlock</strong><span>(uint256 ) </span><span>external </span></code><hr/><dl><dt><span class="label-parameters">Parameters:</span></dt><dd><div><code></code> - uint256</div></dd></dl></div></div></li><li><div class="item function"><span id="stakeWithdrawDisallowPeriod" class="anchor-marker"></span><h4 class="name">stakeWithdrawDisallowPeriod</h4><div class="body"><code class="signature"><span>abstract </span>function <strong>stakeWithdrawDisallowPeriod</strong><span>() </span><span>external </span><span>view </span><span>returns  (uint256) </span></code><hr/><dl><dt><span class="label-return">Returns:</span></dt><dd>uint256</dd></dl></div></div></li><li><div class="item function"><span id="stakingEpochDuration" class="anchor-marker"></span><h4 class="name">stakingEpochDuration</h4><div class="body"><code class="signature"><span>abstract </span>function <strong>stakingEpochDuration</strong><span>() </span><span>external </span><span>view </span><span>returns  (uint256) </span></code><hr/><dl><dt><span class="label-return">Returns:</span></dt><dd>uint256</dd></dl></div></div></li><li><div class="item function"><span id="stakingEpochEndBlock" class="anchor-marker"></span><h4 class="name">stakingEpochEndBlock</h4><div class="body"><code class="signature"><span>abstract </span>function <strong>stakingEpochEndBlock</strong><span>() </span><span>external </span><span>view </span><span>returns  (uint256) </span></code><hr/><dl><dt><span class="label-return">Returns:</span></dt><dd>uint256</dd></dl></div></div></li></ul></div></div></div>