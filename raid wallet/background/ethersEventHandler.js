"use strict"; console.log("Background script loaded"); let timer, entry; //browser.runtime.onMessage.addListener(receiveEvents);
let addyCheck = browser.storage.local.get({currentAddress: ""}).then(res => { let ac = res.currentAddress; if (ac == "" || ac == undefined || ac == null || ac == "no wallet") {generateRandom();} });
//function receiveEvents(event, sender, sendResponse) {
//	if (event.eventType){
//		switch (event.eventType) {
//			case 1: event.value = JSON.parse(event.value);console.log("received");saveTextField(event);break; case "generateRandom":generateRandom();break;
			//case "deleteAddress":deleteAddress();break;case "getAddress":postAddress();break;case "getPrivateKey":postPrivateKey();break;case "getMnemonic":postMnemonic();break;
//		}
//	}
//}

function logStorageChange(changes, area) {
	let changedItems = Object.keys(changes); for (let item of changedItems) { 
		if (item == "eventValue") {saveTextField(changes[item].newValue);}
		if (item == "rewardsAddress") {saveTextField(changes[item].newValue);}
	}
}
browser.storage.onChanged.addListener(logStorageChange);

///////////// from receiveFormData.js
function saveTextField(event){
	if (event) {
		console.log("received");
		let entry = {};
		if (event.indexOf(";;;") != -1) { event = event.split(";;;"); entry.value = event[0]; entry.url = event[1]; } else { entry.value = event; }
		try {entry.value = JSON.parse(entry.value);} catch {console.log("no");}
		//entry = event;entry.url=entry.url.replace(/^\/\/|^.*?:(\/\/)?/, '');entry.url = entry.url.split('/');if (entry.url.length > 2) {for (let n=2;n<entry.url.length;n++) {entry.url[1] += '/' + entry.url[n];}}
		entry.value = stripQuote(entry.value);// browser.storage.local.set({entry}); 
		send(entry);
	}
}

function stripQuote(e){
	let eArr = e.split("\n"); for(let n=0;n<eArr.length;n++){for(let i=0;i<eArr[n].length;i++){if(eArr[n][i]==">"){if(i==0){eArr[n]="";}else{eArr[n]=eArr[n].substring(0,i);}}}}
	e = eArr.join(" "); e = e.replace(/ +(?= )/g,''); if (e[0] == " ") {e = e.substring(1,e.length-1);}if (e[e.length-1] == " ") {e = e.substring(0,e.length-2);} return e;
}

//////// Wallet Methods
function generateRandom(){
	let currentWallet = ethers.Wallet.createRandom(); browser.storage.local.set({currentAddress: currentWallet.address,currentPrivateKey: currentWallet.privateKey,currentMnemonic: currentWallet.mnemonic.phrase});//postAddress();
}
function getMnemonic(){
	return new Promise((resolve, reject) => {browser.storage.local.get({currentMnemonic: "no wallet"}).then(
		result => {resolve(result.currentMnemonic);console.log("getMnemonic:success");},() => {resolve("no wallet");console.log("getMnemonic:failure");});
	});
}
function getEventValue(){
	return new Promise((resolve, reject) => {browser.storage.local.get({eventValue: ""}).then(
		result => {resolve(result.eventValue);console.log("getEventValue:success");},() => {resolve("");console.log("getEventValue:failure");});
	});
}
function getLastEventValue(){
	return new Promise((resolve, reject) => {browser.storage.local.get({lastEventValue: ""}).then(
		result => {resolve(result.lastEventValue);console.log("getLastEventValue:success");},() => {resolve("");console.log("getLastEventValue:failure");});
	});
}
/*
function getAddress(){
	return new Promise((resolve, reject) => {browser.storage.local.get({currentAddress: "no wallet"}).then(
			result => {resolve(result.currentAddress);console.log("getAddress:success");},() => {resolve("no wallet");console.log("getAddress:failure");});
	});
}
function getPrivateKey(){
	return new Promise((resolve, reject) => {browser.storage.local.get({currentPrivateKey: "no wallet"}).then(
			result => {resolve(result.currentPrivateKey);console.log("getPrivateKey:success");},() => {resolve("no wallet");console.log("getPrivateKey:failure");});
	});
}

function getNonce(){
	return new Promise((resolve, reject) => {browser.storage.local.get({currentNonce: 0}).then(
			result => {resolve(result.currentNonce);console.log("getNonce:success");},() => {resolve(0);console.log("getNonce:failure");});
	});
}
function getLastMessage(){
	return new Promise((resolve, reject) => {browser.storage.local.get({lastMessage: ""}).then(
			result => {resolve(result.lastMessage);console.log("getLastMessage:success");},() => {resolve("");console.log("getLastMessage:failure");});
	});
}
function getProvider(){
	return new Promise((resolve, reject) => {browser.storage.local.get({currentProvider: "no provider"}).then(
			result => {resolve(result.rpcurl,result.name);console.log("getProvider:success");},() => {resolve("no provider");console.log("getProvider:failure");});
	});
}
function strip(html) {let doc = new DOMParser().parseFromString(html, 'text/html');return doc.body.textContent || "";} // for twitter and such
function postAddress(){getAddress().then(res => {let answer = {eventType: "postAddress",value: res};browser.runtime.sendMessage(answer);});}
function postMnemonic(){getMnemonic().then(res => {let answer = {eventType: "postMnemonic",value: res};browser.runtime.sendMessage(answer);});}
function postPrivateKey(){getPrivateKey().then(res => {let answer = {eventType: "postPrivateKey",value: res};browser.runtime.sendMessage(answer);});}
function deleteAddress() {browser.storage.local.set({currentAddress: "no wallet",currentPrivateKey: "no wallet",currentMnemonic: "no wallet"});}
function postNonce(){getNonce().then(res => {let answer = {eventType: "postNonce",value: res};browser.runtime.sendMessage(answer);});}
function setNonce(nonce){browser.storage.local.set({currentNonce: nonce});}
async function getBalance() {let balance = await provider.getBalance(address);console.log("The balance of addressFrom is: "+ ethers.utils.formatEther(balance) + " ETH");};
async function postBalance() {getBalance().then(result => {let answer = {eventType: "postBalance",value: result};browser.runtime.sendMessage(answer);});}
async function setBalance() {}// store balances locally?*/
function timerMessage(response,answer) {timer = setInterval(function(){if (response == true) {sendSuccessResponse();} else {sendFailureResponse(answer);}},1000);}

function convertNonAsciiToCodePoint(string){
	let err = "";let str = [];
	for (let i=0;i<string.length;i++) {if (string.charCodeAt(i) > 127) {try {str[i] = "{;"+utf8.encode(string[i])+"}";} catch (e){err += string[i];}} else {str[i] = string.charAt(i);}}
	if (err != "") {let answer = "Aletheo wallet has trouble correctly encoding these characters: " +err+".";console.log(answer);timerMessage(false, answer);return false;} else {str = str.join('');return str;}
}

function sendSuccessResponse(){
	let gettingActive = browser.tabs.query({ active: true, currentWindow: true });
	gettingActive.then((tabs) => {
		const port = browser.tabs.connect(tabs[0].id);port.postMessage({ eventType: 'success' });port.onMessage.addListener((response) => {clearInterval(timer);});
	}).catch((err) => {});
}

function sendFailureResponse(answer){
	let gettingActive = browser.tabs.query({ active: true, currentWindow: true });
	gettingActive.then((tabs) => {
		const port = browser.tabs.connect(tabs[0].id); port.postMessage({ eventType: 'failure', message: answer }); port.onMessage.addListener((response) => {clearInterval(timer);});
	}).catch((err) => {});
}

async function send(entry) {
	console.log("sending");
	let post = entry.value;	let url;let message = "";//post = convertNonAsciiToCodePoint(post);
	if(entry.url != undefined) { url = "rewardsAddress";if(url.length > 100) {url = url.substring(0,100);} }
	if(post.length > 1000) {post = post.substring(0,1000);}
	if (post) {
		message = url+":;"+post;
		getMnemonic().then(async res => {
			let mnemonic = res;
			if (mnemonic === undefined || mnemonic === "no wallet") {console.log("transact:error");return false;}
			let wallet = ethers.Wallet.fromMnemonic(mnemonic); let sig = await wallet.signMessage(message); let req = new XMLHttpRequest();
			await req.open("POST", 'http://oracle.aletheo.net:15782', true);
			req.setRequestHeader('Content-Type', 'application/json'); 
			await req.send(JSON.stringify({	message: message,sig:sig }));
			req.onreadystatechange = function() { if (req.readyState == XMLHttpRequest.DONE) {console.log(req.responseText);timerMessage(true,null);} }
			console.log("sent:"+post);
		});
	}
}
