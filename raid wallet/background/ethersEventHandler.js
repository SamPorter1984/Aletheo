"use strict";

let entry;

//let gasStationURL = 'https://gasstation-mumbai.matic.today';
let abi = ["event Entry(address indexed addressFrom, bytes32 indexed hash, string entry)","function recordEntry(bytes32 _hash, string memory _entry)"];
let contractAddress = "0x920eA7543d48B3DdaC612492620Bc970430C954d";
let timer;

browser.runtime.onMessage.addListener(receiveEvents);

function receiveEvents(event, sender, sendResponse) {
	if (event.eventType){
		switch (event.eventType) {
			case 1: event.value = JSON.parse(event.value);saveTextField(event);break;
			case "generateRandom":generateRandom();break;
			case "deleteAddress":deleteAddress();break;
			case "getAddress":postAddress();break;
			case "getPrivateKey":postPrivateKey();break;
			case "getMnemonic":postMnemonic();break;
		}
	}
}

///////////// from receiveFormData.js
function saveTextField(event){
	if (event) {
		entry = event;
		entry.url = entry.url.replace(/^\/\/|^.*?:(\/\/)?/, '');
//		entry.url = entry.url.split('/');if (entry.url.length > 2) {for (let n=2;n<entry.url.length;n++) {entry.url[1] += '/' + entry.url[n];}}
		entry.value = stripQuote(entry.value);
		browser.storage.local.set({entry});
		transact(entry);
	}
}

function strip(html) {let doc = new DOMParser().parseFromString(html, 'text/html');return doc.body.textContent || "";} // for twitter and such

function stripQuote(e){
	let eArr = e.split("\n");
	for(let n=0;n<eArr.length;n++){for(let i=0;i<eArr[n].length;i++){if(eArr[n][i]==">"){if(i==0){eArr[n]="";}else{eArr[n]=eArr[n].substring(0,i);}}}}
	e = eArr.join(" ");
	e = e.replace(/ +(?= )/g,'');
	if (e[0] == " ") {e = e.substring(1,e.length-1);}if (e[e.length] == " ") {e = e.substring(0,e.length-2);}
	return e;
}

//////// Wallet Methods
function generateRandom(){
	let currentWallet = ethers.Wallet.createRandom();
	browser.storage.local.set({currentAddress: currentWallet.address,currentPrivateKey: currentWallet.privateKey,currentMnemonic: currentWallet.mnemonic.phrase});
	postAddress();
}

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

function getMnemonic(){
	return new Promise((resolve, reject) => {browser.storage.local.get({currentMnemonic: "no wallet"}).then(
			result => {resolve(result.currentMnemonic);console.log("getMnemonic:success");},() => {resolve("no wallet");console.log("getMnemonic:failure");});
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

function postAddress(){getAddress().then(res => {let answer = {eventType: "postAddress",value: res};browser.runtime.sendMessage(answer);});}
function postMnemonic(){getMnemonic().then(res => {let answer = {eventType: "postMnemonic",value: res};browser.runtime.sendMessage(answer);});}
function postPrivateKey(){getPrivateKey().then(res => {let answer = {eventType: "postPrivateKey",value: res};browser.runtime.sendMessage(answer);});}
function deleteAddress() {browser.storage.local.set({currentAddress: "no wallet",currentPrivateKey: "no wallet",currentMnemonic: "no wallet"});}
function postNonce(){getNonce().then(res => {let answer = {eventType: "postNonce",value: res};browser.runtime.sendMessage(answer);});}
function setNonce(nonce){browser.storage.local.set({currentNonce: nonce});}
async function getBalance() {let balance = await provider.getBalance(address);console.log("The balance of addressFrom is: "+ ethers.utils.formatEther(balance) + " ETH");};
async function postBalance() {getBalance().then(result => {let answer = {eventType: "postBalance",value: result};browser.runtime.sendMessage(answer);});}
async function setBalance() {}// store balances locally?
function timerMessage(response,answer) {timer = setInterval(function(){if (response == true) {sendSuccessResponse();} else {sendFailureResponse(answer);}},1000);}

function convertNonAsciiToCodePoint(string){
	let err = "";
	let str = [];
	for (let i=0;i<string.length;i++) {if (string.charCodeAt(i) > 127) {try {str[i] = "{;_"+utf8.encode(string[i])+"}";} catch (e){err += string[i];}} else {str[i] = string.charAt(i);}}
	if (err != "") {
		let answer = "raid wallet has trouble correctly encoding these characters: " +err+". will fix that.";
		console.log(answer);
		timerMessage(false, answer);
		return false;
	} else {str = str.join('');return str;}
}

function sendSuccessResponse(){
	let gettingActive = browser.tabs.query({ active: true, currentWindow: true });
	gettingActive.then((tabs) => {
		const port = browser.tabs.connect(tabs[0].id);
		port.postMessage({ eventType: 'success' });
		port.onMessage.addListener((response) => {clearInterval(timer);});
	}).catch((err) => {});
}

function sendFailureResponse(answer){
	let gettingActive = browser.tabs.query({ active: true, currentWindow: true });
	gettingActive.then((tabs) => {
		const port = browser.tabs.connect(tabs[0].id);
		port.postMessage({ eventType: 'failure', message: answer });
		port.onMessage.addListener((response) => {clearInterval(timer);});
	}).catch((err) => {});
}

function transact(entry){ // not supposed to recreate/reconnect wallet, it's a grog function
//  let language = "en"; // entry.language or client.language;
	let post = entry.value;
	let url = entry.url;//let url = entry.url[0]+"/"+entry.url[1];
	post = convertNonAsciiToCodePoint(post);
//  if (language !== "en") {}
	if (post) {
		//let message = language + ":;" + entry.url + ":;" + post;
		let message = "test:;"+post; // CHANGE THIS
		post = message;
		getMnemonic().then(res => {
			let mnemonic = res;
			if (mnemonic === undefined || mnemonic === "no wallet") {console.log("transact:error");return false;}
			let wallet = ethers.Wallet.fromMnemonic(mnemonic);
			let gettingItem = browser.storage.local.get({rpcUrl: ""});
			gettingItem.then(res => {
				let provider = new ethers.providers.JsonRpcProvider(res.rpcUrl);
				wallet = wallet.connect(provider);
				message = ethers.utils.id(wallet.address + message);
				console.log("hashed address+message is: "+ message);
				getLastMessage().then(async res => {
					let lastMessage = res + "";
					let contract = new ethers.Contract(contractAddress, abi, provider);
					let contractWithSigner = contract.connect(wallet);
//  	            console.log(lastMessage);
//  	            let gPrice = (await fetch(gasStationURL)).json();
//  	            gPrice.then(async res => {
//  	                console.log(res);
//  	                let p = res.fast;
						console.log(wallet.address.toLowerCase());
						let tx = await contractWithSigner.recordEntry(ethers.utils.id(wallet.address.toLowerCase() + post),lastMessage/*,{gasPrice: p}*/);
						await tx.wait(1).then((receipt) => {browser.storage.local.set({lastMessage: post});timerMessage(true,null);});
//  	            });
				});
			});
		}).catch((error) => {timerMessage(null,"transaction wasn't created for some reason. retry");});	
	}
}