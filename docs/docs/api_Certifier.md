---
id: Certifier
title: Certifier
---

<div class="contract-doc"><div class="contract"><h2 class="contract-header"><span class="contract-kind">contract</span> Certifier</h2><p class="base-contracts"><span>is</span> <a href="eternal-storage_OwnedEternalStorage.html">OwnedEternalStorage</a><span>, </span><a href="interfaces_ICertifier.html">ICertifier</a></p><p class="description">Allows validators to use a zero gas price for their service transactions (see https://wiki.parity.io/Permissioning.html#gas-price for more info).</p><div class="source">Source: <a href="https://github.com/poanetwork/posdao-contracts/blob/v0.1.0/contracts/Certifier.sol" target="_blank">contracts/Certifier.sol</a></div></div><div class="index"><h2>Index</h2><ul><li><a href="Certifier.html#Confirmed">Confirmed</a></li><li><a href="Certifier.html#Revoked">Revoked</a></li><li><a href="Certifier.html#_certify">_certify</a></li><li><a href="Certifier.html#certified">certified</a></li><li><a href="Certifier.html#certify">certify</a></li><li><a href="Certifier.html#initialize">initialize</a></li><li><a href="Certifier.html#revoke">revoke</a></li></ul></div><div class="reference"><h2>Reference</h2><div class="events"><h3>Events</h3><ul><li><div class="item event"><span id="Confirmed" class="anchor-marker"></span><h4 class="name">Confirmed</h4><div class="body"><code class="signature">event <strong>Confirmed</strong><span>(address who) </span></code><hr/><div class="description"><p>Emitted by the `certify` function when the specified address is allowed to use a zero gas price for its transactions.</p></div><dl><dt><span class="label-parameters">Parameters:</span></dt><dd><div><code>who</code> - Specified address allowed to make zero gas price transactions.</div></dd></dl></div></div></li><li><div class="item event"><span id="Revoked" class="anchor-marker"></span><h4 class="name">Revoked</h4><div class="body"><code class="signature">event <strong>Revoked</strong><span>(address who) </span></code><hr/><div class="description"><p>Emitted by the `revoke` function when the specified address is denied using a zero gas price for its transactions.</p></div><dl><dt><span class="label-parameters">Parameters:</span></dt><dd><div><code>who</code> - Specified address for which zero gas price transactions are denied.</div></dd></dl></div></div></li></ul></div><div class="functions"><h3>Functions</h3><ul><li><div class="item function"><span id="_certify" class="anchor-marker"></span><h4 class="name">_certify</h4><div class="body"><code class="signature">function <strong>_certify</strong><span>(address _who) </span><span>internal </span></code><hr/><div class="description"><p>An internal function for the `certify` and `initialize` functions.</p></div><dl><dt><span class="label-parameters">Parameters:</span></dt><dd><div><code>_who</code> - The address for which transactions with a zero gas price must be allowed.</div></dd></dl></div></div></li><li><div class="item function"><span id="certified" class="anchor-marker"></span><h4 class="name">certified</h4><div class="body"><code class="signature">function <strong>certified</strong><span>(address _who) </span><span>external </span><span>view </span><span>returns  (bool) </span></code><hr/><div class="description"><p>Returns a boolean flag indicating whether the specified address is allowed to use zero gas price transactions. Returns `true` if either the address is certified using the `_certify` function or if `ValidatorSet.isReportValidatorValid` returns `true` for the specified address.</p></div><dl><dt><span class="label-parameters">Parameters:</span></dt><dd><div><code>_who</code> - The address for which the boolean flag must be determined.</div></dd><dt><span class="label-return">Returns:</span></dt><dd>bool</dd></dl></div></div></li><li><div class="item function"><span id="certify" class="anchor-marker"></span><h4 class="name">certify</h4><div class="body"><code class="signature">function <strong>certify</strong><span>(address _who) </span><span>external </span></code><hr/><div class="description"><p>Allows the specified address to use a zero gas price for its transactions. Can only be called by the `owner`.</p></div><dl><dt><span class="label-modifiers">Modifiers:</span></dt><dd><a href="eternal-storage_OwnedEternalStorage.html#onlyOwner">onlyOwner </a></dd><dt><span class="label-parameters">Parameters:</span></dt><dd><div><code>_who</code> - The address for which zero gas price transactions must be allowed.</div></dd></dl></div></div></li><li><div class="item function"><span id="initialize" class="anchor-marker"></span><h4 class="name">initialize</h4><div class="body"><code class="signature">function <strong>initialize</strong><span>(address _certifiedAddress) </span><span>external </span></code><hr/><div class="description"><p>Initializes the contract at network startup. Must be called by the constructor of the `Initializer` contract on the genesis block.</p></div><dl><dt><span class="label-parameters">Parameters:</span></dt><dd><div><code>_certifiedAddress</code> - The address for which a zero gas price must be allowed.</div></dd></dl></div></div></li><li><div class="item function"><span id="revoke" class="anchor-marker"></span><h4 class="name">revoke</h4><div class="body"><code class="signature">function <strong>revoke</strong><span>(address _who) </span><span>external </span></code><hr/><div class="description"><p>Denies the specified address usage of a zero gas price for its transactions. Can only be called by the `owner`.</p></div><dl><dt><span class="label-modifiers">Modifiers:</span></dt><dd><a href="eternal-storage_OwnedEternalStorage.html#onlyOwner">onlyOwner </a></dd><dt><span class="label-parameters">Parameters:</span></dt><dd><div><code>_who</code> - The address for which transactions with a zero gas price must be denied.</div></dd></dl></div></div></li></ul></div></div></div>