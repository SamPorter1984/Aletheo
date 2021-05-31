/*
 * Copyright (c) 2018. Stephan Mahieu
 *
 * This file is subject to the terms and conditions defined in
 * file 'LICENSE', which is part of this source code package.
 */
'use strict';

browser.runtime.onMessage.addListener(event => {
	if (event.eventType) {
		if(event.eventType == "postAddress") {showAddress(event.value);}
		if(event.eventType == "postPrivateKey") {showPrivateKey(event.value);} // not recommended. needs trusted page
		if(event.eventType == "postMnemonic") {showMnemonic(event.value);}
	}
});

let rewardsAddress;
let rpcProvider;

document.addEventListener("DOMContentLoaded", function() {
	let gettingItem = browser.storage.local.get({rewardsAddress: ""});
	gettingItem.then(res => {
		if (res.rewardsAddress != "" && res.rewardsAddress != undefined && res.rewardsAddress != null) {
			document.getElementById("rewardsAddress").innerHTML = res.rewardsAddress;
			document.getElementById("rewardsAddressDivSet").style.display = "none";
			document.getElementById("rewardsAddressDiv").style.display = "block";
		}
	});
	gettingItem = browser.storage.local.get({rpcUrl: ""});
	gettingItem.then(res => {
		if (res.rpcUrl != "" && res.rpcUrl != undefined && res.rpcUrl != null) {
			document.getElementById("rpcProvider").innerHTML = res.rpcUrl;
			document.getElementById("rpcProviderDivSet").style.display = "none";
			document.getElementById("rpcProviderDiv").style.display = "block";
		}
	});
	let requestMessage = {eventType: "getAddress"};
	browser.runtime.sendMessage(requestMessage);
	document.getElementById('rewardsAddressInput').addEventListener("change", function(event){rewardsAddress = event.target.value;});
	document.getElementById('rpcProviderInput').addEventListener("change", function(event){rpcProvider = event.target.value;});
	document.getElementById("setRewardsAddress").addEventListener("click", function(event){event.preventDefault();setRewardsAddress();});
	document.getElementById("setRpcProvider").addEventListener("click", function(event){event.preventDefault();setRpcProvider();});
	document.getElementById("editRewardsAddress").addEventListener("click", function(event){event.preventDefault();editRewardsAddress();});
	document.getElementById("editRpcProvider").addEventListener("click", function(event){event.preventDefault();editRpcProvider();});
	document.getElementById("showPrivateKey").addEventListener("click", function(event){event.preventDefault();requestPrivateKey();});
	document.getElementById("showMnemonic").addEventListener("click", function(event){event.preventDefault();requestMnemonic();});
	document.getElementById("hidePrivateKey").addEventListener("click", function(event){event.preventDefault();event.stopPropagation();hidePrivateKey();});
	document.getElementById("hideMnemonic").addEventListener("click", function(event){event.preventDefault();event.stopPropagation();hideMnemonic();});
	document.getElementById("deleteAddress").addEventListener("click", function(event){
		event.preventDefault();
		event.stopPropagation();
		let customPrompt = document.getElementById("customPrompt");
		customPrompt.style.display = "block";
		let cancelButton = document.getElementById("customPromptCancel");
		let confirmButton = document.getElementById("customPromptConfirm");
		cancelButton.addEventListener("click", function(){customPrompt.style.display = "none";return;});
		confirmButton.addEventListener("click", function(){
			customPrompt.style.display = "none";
			document.getElementById("address").innerHTML = "no wallet";
			document.getElementById("privateKey").innerHTML = "no wallet";
			document.getElementById("mnemonic").innerHTML = "no wallet";
			hidePrivateKey();
			hideMnemonic();
			generateButton();
			deleteAddress();
		});
	});
	document.getElementById("copyAddress").addEventListener("click", function(event){event.preventDefault();event.stopPropagation();copyAddress();});
	document.getElementById("copyMnemonic").addEventListener("click", function(event){event.preventDefault();event.stopPropagation();copyMnemonic();});
	document.getElementById("copyPrivateKey").addEventListener("click", function(event){event.preventDefault();event.stopPropagation();copyPrivateKey();});
});

function showAddress(address) {
	if (address == "no wallet") {generateButton();}
	else {
		document.getElementById("address").innerHTML = address;
		document.getElementById("generate").style.display = "none";
		document.getElementById("addressDiv").style.display = "block";
	}
}

function requestPrivateKey() {let request = {eventType: "getPrivateKey"};browser.runtime.sendMessage(request);}

function requestMnemonic() {let request = {eventType: "getMnemonic"};browser.runtime.sendMessage(request);}

function showPrivateKey(privateKey) {
	if (privateKey !== "no wallet") {
		document.getElementById("privateKey").innerHTML = privateKey;
		document.getElementById("showPrivateKey").style.display = "none";
		document.getElementById("privateKeyDiv").style.display = "block";
	}
}

function showMnemonic(mnemonic) {
	if (mnemonic !== "no wallet") {
		document.getElementById("mnemonic").innerHTML = mnemonic;
		document.getElementById("showMnemonic").style.display = "none";
		document.getElementById("mnemonicDiv").style.display = "block";
	}
}

function hidePrivateKey() {
	document.getElementById("privateKey").innerHTML = "no wallet";
	document.getElementById("showPrivateKey").style.display = "block";
	document.getElementById("privateKeyDiv").style.display = "none";
}

function hideMnemonic() {
	document.getElementById("mnemonic").innerHTML = "no wallet";
	document.getElementById("showMnemonic").style.display = "block";
	document.getElementById("mnemonicDiv").style.display = "none";
}

function generateButton() {
	let genBut = document.getElementById("generate");
	genBut.style.display = "block";
	document.getElementById("addressDiv").style.display = "none";
	genBut.addEventListener("click", generateNewAddress);
}

function generateNewAddress() {let request = {eventType: "generateRandom"};browser.runtime.sendMessage(request);}

function deleteAddress() {let request = {eventType: "deleteAddress"};browser.runtime.sendMessage(request);}

function setRewardsAddress() {
	document.getElementById("rewardsAddressDivSet").style.display = "none";
	document.getElementById("rewardsAddressDiv").style.display = "block";
	document.getElementById("rewardsAddress").innerHTML = rewardsAddress;
	browser.storage.local.set({rewardsAddress: rewardsAddress});
}

function setRpcProvider() {
	document.getElementById("rpcProviderDivSet").style.display = "none";
	document.getElementById("rpcProviderDiv").style.display = "block";
	document.getElementById("rpcProvider").innerHTML = rpcProvider;
	browser.storage.local.set({rpcUrl: rpcProvider});
}

function editRewardsAddress() {
	document.getElementById("rewardsAddressDivSet").style.display="block";
	rewardsAddress=document.getElementById("rewardsAddress").innerHTML;
	document.getElementById("rewardsAddressInput").value=rewardsAddress;
	document.getElementById("rewardsAddressDiv").style.display="none";
}

function editRpcProvider() {
	let temp=document.getElementById("rpcProviderDivSet");
	temp.style.display="block";rpcProvider=document.getElementById("rpcProvider").innerHTML;temp.value=rpcProvider;document.getElementById("rpcProviderDiv").style.display="none";
}

function copyAddress() {let copy = document.getElementById("address").innerHTML;tempTextArea(copy);}
function copyMnemonic() {let copy = document.getElementById("mnemonic").innerHTML;tempTextArea(copy);}
function copyPrivateKey() {let copy = document.getElementById("privateKey").innerHTML;tempTextArea(copy);}

function tempTextArea(copy) {
	let ar = document.createElement("textarea");
	document.body.appendChild(ar);
	ar.value = copy;
	ar.select();
	ar.setSelectionRange(0, 99999);
	document.execCommand("copy");
	ar.remove();
}
