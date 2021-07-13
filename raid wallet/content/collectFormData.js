/*
 * Copyright (c) 2018. Stephan Mahieu
 *
 * This file is subject to the terms and conditions defined in
 * file 'LICENSE', which is part of this source code package.
 */
// Also contains parts of showFormData.js. Modified by SamPorter1984

// quick reply on 2ch.hk main page not working for now since default event is being prevented. to reply to the thread you have to visit thread page. 
// can be fixed in the future

'use strict';

let eventQueue = [];
let awaitingResponse = true;
let button = undefined;
let txtNode;
let lastEventVal = "event value";
let responseDiv;
let defaultStyle = "visibility:hidden;opacity:0.8;font:bold 12px sans-serif;z-index:2147483;border:1px solid #000;background:#fff;position:fixed;bottom:3%;right:3%;height:35px;width:170px";
browser.runtime.onConnect.addListener((port,msg) => {
	port.onMessage.addListener((msg) => {port.postMessage({eventType:"ok"});awaitingResponse = null;console.log(msg.msg);responseWindow(msg.eventType,msg.msg);});
});
// the order has to be from most popular to least popular
let filter = ["4chan.","4channel."/*,"twitter.com"*/,"ylilauta.","komica.","kohlchan.","diochan.","ptchan.","hispachan.","2ch.hk","indiachan.","2chan."/*,"github.com","bitcointalk.org",
"ethereum-magicians.org","forum.openzeppelin.com"*/,"wrongthink.net","endchan.net","krautchan."];
//----------------------------------------------------------------------------
// EventQueue handling methods
//----------------------------------------------------------------------------

function responseWindow(type,msg) {
	if(responseDiv) {
		responseDiv.innerHTML = msg;
		let color ="green"; let opacity = 0.8; if(type == true){setTimeout(()=>{responseDiv.setAttribute("style",defaultStyle);},5000);} else {
			color = "red";
			setTimeout(()=>{responseDiv.setAttribute("style",defaultStyle);},15000);
		}
		responseDiv.setAttribute("style","color:#000;visibility:visible;opacity:"+opacity+";font:bold 12px sans-serif;z-index:2147483;border:1px solid #000;background:"+color+";position:fixed;bottom:3%;right:3%;height:35px;width:170px");
	}
}


function processEventQueue() { // leaving queue almost as is in case if double-event could still happen even with button disabled.
	if (0 < eventQueue.length) {
		let event;
		for (let it=0; it<eventQueue.length; it++) {event = eventQueue[it];if(event.eventType == 1) {_processContentEvent(event);break;}}
		eventQueue = [];
	}
}

function _processContentEvent(event) {
	// get current content (lazily load)
	let theContent = _getContent(event);
	if (theContent.length > 0 && _containsPrintableContent(theContent)){
		event.value = JSON.stringify(theContent);
		event.last = (new Date()).getTime();
		console.log("Send content-event for " + event.node + " to background-script: " + event.value);
		event.node.listenerAdded = false;
		let entry = event.value+";;;"+event.url;
		browser.storage.local.set({eventValue: entry});
	//	browser.runtime.sendMessage(event);
	}
}

function _containsPrintableContent(value) {return value.replace('&nbsp;','').replace(/[^\x20-\x7E]/g, '').replace(/\s/g,'').length > 0;}

//----------------------------------------------------------------------------
// Event listeners
//----------------------------------------------------------------------------

function onContentChanged(event) {
	let t = event.target;
	let n = t.nodeName.toLowerCase();
	console.log("content changed");
	if (_isNotIrrelevantInfo(t)) {
		if ("keyup" === event.type) {if ("input" === n) return;if (! (event.key.length === 1 || ("Backspace" === event.key || "Delete" === event.key || "Enter" === event.key))) return;}
		if ("input" === n && !_isTextInputSubtype(t.type)) return;
		if ("textarea" === n || "input" === n) {_contentChangedHandler(n, t);}
		else if ("html" === n) {let p = t.parentNode;if (p && "on" === p.designMode) {_contentChangedHandler("html", p);}}
		else if ("body" === n || "div" === n) {
			let doc = t.ownerDocument;let e = t;if (("on" === doc.designMode) || _isContentEditable(e)) {_contentChangedHandler("body" === n ? "iframe" : "div", e);}
		}
	}
}
let enode, etype, eid, ename, eformid, epagetitle;
function _contentChangedHandler(type, node) {
	let location = node.ownerDocument.location;
	console.log("default location is: " + location);
	let nodeFix;
	let check = document.querySelector(".aletheoClass");
	if(check){check.classList.remove("aletheoClass");}
	if (window.location.href.indexOf("4chan") != -1) {
		nodeFix = document.querySelector("#qrForm > div > textarea");
		if(nodeFix) {
			nodeFix.classList.add("aletheoClass");
			console.log(nodeFix);
			if (nodeFix === node) {
				if (window.location.href.indexOf("thread") == -1) {let qrTid = document.getElementById("qrTid");location = location + "thread/" + qrTid.innerHTML + ".html/";}
			}
		}
	}
	if (window.location.href.indexOf("diochan") != -1 || window.location.href.indexOf("ptchan") != -1) {
		nodeFix = document.querySelector("#quick-reply > div > table > tbody > tr > td > textarea");
		if(nodeFix) {nodeFix.classList.add("aletheoClass");console.log(nodeFix);}
	}
	if (window.location.href.indexOf("hispachan") != -1) {
		nodeFix = document.querySelector("#quick_reply > table > tbody > tr > td > textarea");
		if(nodeFix) {
			nodeFix.classList.add("aletheoClass");
			console.log(nodeFix);
			if (nodeFix === node) {
				if (window.location.href.indexOf("res") == -1) {
					let qrTid = document.querySelector(".quick_reply_title"); let str = qrTid.innerHTML; let res = str.substring(18); location = location + "res/" + res + ".html/";
				}
			}
		}
	}
	let name = (node.name) ? node.name : ((node.id) ? node.id : "");
	console.log("new content at "+name);
	// add to queue (if not already queued)
//	if (button) {button.remove();}
	button = findFields(node);
	console.log(button);
	if(node.listenerAdded != true) {
		node.listenerAdded = true;
		button.addEventListener("click", function(clickEvent){
			node.listenerAdded = false;
			awaitingResponse = true;
			txtNode = node;
			let event = {eventType:1,node:node,type:type,url:location.href,incognito:browser.extension.inIncognitoContext,last:null,value:null};
			if (!_alreadyQueued(event)) {eventQueue.push(event);}
			processEventQueue();
			console.log("clicked");
			responseDiv.innerHTML = "awaiting response...";
			responseDiv.setAttribute("style",defaultStyle);
			responseDiv.style.visibility = "visible";
		});
	}
}

//----------------------------------------------------------------------------
// HTML Field/Form helper methods
//----------------------------------------------------------------------------

function _isTextInputSubtype(type) {return ("text" === type || "textarea" === type);}

function _getContent(event) {
	let theContent = "";
	try {
		switch(event.type) {
			case "textarea":case "input":theContent = event.node.value;break;
			case "html":theContent = event.node.body.innerHTML;break;
			case "div":case "iframe":theContent = event.node.innerHTML;break;
		}
	} catch(e) {}// possible "can't access dead object" TypeError, DOM object destroyed
	return theContent;
}

function _getId(element) {return (element.id) ? element.id : ((element.name) ? element.name : "");}

function _getClassOrNameOrId(element) {
	return element.classList.contains('aletheoClass') ? "aletheoClass" : (element.name && element.name.length > 0) ? element.name : element.id;
}

function _getFormId(element) {
	let insideForm = false;
	let parentElm = element;
	while(parentElm && !insideForm) {parentElm = parentElm.parentNode;insideForm = (parentElm && "FORM" === parentElm.tagName);}
	return (insideForm && parentElm) ? _getId(parentElm) : "";
}

function _getHost(aLocation) {if (aLocation.protocol === "file:") {return "localhost";} else {return aLocation.host;}}

function _isContentEditable(element) {
	if (element.contentEditable === undefined) {return false;}
	if ("inherit" !== element.contentEditable) {return ("true" === element.contentEditable);}
	let doc = element.ownerDocument;
	let effectiveStyle = doc.defaultView.getComputedStyle(element, null);
	let propertyValue = effectiveStyle.getPropertyValue("contentEditable");
	if ("inherit" === propertyValue && element.parentNode.style) {return _isContentEditable(element.parentNode);}
	return ("true" === propertyValue);
}

function _isDisplayed(elem) {
	let display = _getEffectiveStyle(elem, "display");
	if ("none" === display) return false;
	let visibility = _getEffectiveStyle(elem, "visibility");
	if ("hidden" === visibility || "collapse" === visibility) return false;
	let opacity = _getEffectiveStyle(elem, "opacity");
	if (0 === opacity) return false;
	if (elem.parentNode.style) {return _isDisplayed(elem.parentNode);}
	return true;
}

function _getEffectiveStyle(element, property) {
	if (element.style === undefined) {return undefined;}
	let doc = element.ownerDocument;
	let effectiveStyle = doc.defaultView.getComputedStyle(element, null);
	let propertyValue = effectiveStyle.getPropertyValue(property);
	if ("inherit" === propertyValue && element.parentNode.style) {return _getEffectiveStyle(element.parentNode, property);}
	return propertyValue;
}
//----------------------------------------------------------------------------
// Event enqueueing methods
//----------------------------------------------------------------------------

function _alreadyQueued(event) {
	let e;
	for (let it=0; it<eventQueue.length; it++) {e = eventQueue[it];if (e.eventType === event.eventType && e.node === event.node) {return true;}}
	return false;
}
//----------------------------------------------------------------------------
// Add event handlers
//----------------------------------------------------------------------------

function createDomObserver() {
	return new MutationObserver(mutations => {
		mutations.forEach((mutation) => {
			//console.log('Detected a mutation!  type = ' + mutation.type);
			if (mutation.type === 'attributes') {
				const targetElem = mutation.target;
				if ('style' === mutation.attributeName) {
					// style changed
					if (mutation.oldValue && mutation.oldValue.indexOf('display: none')!==-1 && targetElem.style.display !== 'none') {
						// element style became visible, add event handler(s) that were not added previously because the element was invisible
						// console.log('display changed for id:' + targetElem.id + " type:" + targetElem.tagName + " oldValue:" + mutation.oldValue);
						addElementHandlers(targetElem);
					}
				} else {
					// attribute contenteditable or designMode changed
					// console.log('Contenteditable changed ' + targetElem.nodeName  + '  editable = ' + _isContentEditable(targetElem));
					targetElem.addEventListener("keyup", onContentChanged);
				}
			} else if (mutation.addedNodes) {mutation.addedNodes.forEach(elem => {addElementHandlers(elem);});}
		});
	});
}

function addElementHandlers(element) {
	if (element.nodeName) {
		if (element.nodeName == "input") {element.addEventListener('change', onContentChanged);element.addEventListener('paste', onContentChanged);}
		else if (element.nodeName == "textarea"){element.addEventListener("keyup", onContentChanged);element.addEventListener('paste', onContentChanged);}
		if (element.hasChildNodes()) {Array.from(element.childNodes).forEach(elem => addElementHandlers(elem));}
	}
}

function addHandler(selector, eventType, aFunction) {document.querySelectorAll(selector).forEach( (elem) => {elem.addEventListener(eventType, aFunction);});}


// instantiate an observer for adding event handlers to dynamically created DOM elements
for (let it = 0; it<filter.length;it++) {// known bug: fails to deliver some posts
	if (window.location.href.indexOf(filter[it]) != -1) {
		document.querySelector("html").addEventListener("keyup", onContentChanged);
		addHandler("input", "change", onContentChanged);
		addHandler("input,textarea", "paste", onContentChanged);
		createDomObserver().observe(document.querySelector("body"),{childList:true,attributes:true,attributeFilter:['contenteditable','designMode','style'],attributeOldValue:true,subtree:true});
		if(responseDiv == undefined || responseDiv == null){
		responseDiv = document.createElement("div");
		responseDiv.setAttribute("class","oracleResponseDiv");
		responseDiv.innerHTML = "awaiting response...";
		responseDiv.setAttribute("style",defaultStyle);
		responseDiv.style.visibility = "hidden";
		document.body.appendChild(responseDiv);
		let close = document.createElement("a");
		close.innerHTML = "[x]";
		close.addEventListener("click",function(event){event.preventDefault();responseDiv.setAttribute("style",defaultStyle);});
		close.setAttribute("style","position:absolute; right:2px;");
		responseDiv.appendChild(close);
	}
	}
}
//////////////// showFormData.js

function _isNotIrrelevantInfo(node) {
	let irrelevant = ["name","pass","phone","topic","search","sub", "mail","qf-box","find","js-sf-qf","pwd","categ","title","captcha","report","embed","url","subject","email"];
	if (irrelevant.indexOf(node.name) != -1 || irrelevant.indexOf(node.id) != -1) {return false;}
	return true;
}

function findFields(elem) {
	let ii = 0, elemId, div, butt, t;
	if (_isNotIrrelevantInfo(elem)) {
		if (_isTextInputSubtype(elem.type) && _isDisplayed(elem)) {
			if(window.location.href.indexOf("4chan")!=-1){
				t=_getClassOrNameOrId(elem);
				if(t=="aletheoClass"){butt=document.querySelector('div>input[value="Post"]');}
				if(t=="com"){butt=document.querySelector('td>input[value="Post"]');}
				if(document.querySelector("#file-n-submit > input[value='Submit']")) {butt = document.querySelector("#file-n-submit > input[value='Submit']");}
			}
			if (window.location.href.indexOf("2ch.hk") != -1){
			//	elemId = 'letButton'+ elem.type + elem.name;
			//	if (document.getElementById(elemId)) {document.getElementById(elemId).remove();}
			//	butt = _createLetButton(elemId, elem, true);
			//	elem.parentNode.parentNode.insertBefore(div,elem.parentNode);
				if(elem.id=="qr-shampoo"){console.log("dis button");butt=document.querySelector('#qr-submit');} 
				if(elem.id=="shampoo"){butt=document.querySelector('#submit');}
			}
			/*if (window.location.href.indexOf("4chan") != -1 ||window.location.href.indexOf("ylilauta") != -1 || window.location.href.indexOf("komica") != -1|| window.location.href.indexOf("krautchan.") != -1
			|| window.location.href.indexOf("kohlchan") != -1 || window.location.href.indexOf("diochan") != -1 || window.location.href.indexOf("endchan.net") != -1
			|| window.location.href.indexOf("ptchan") != -1 || window.location.href.indexOf("hispachan") != -1 || window.location.href.indexOf("wrongthink.net") != -1) {elem.parentNode.parentNode.appendChild(div);} 
			else if (window.location.href.indexOf("2ch.hk") != -1 || window.location.href.indexOf("adnmb2") != -1
			|| window.location.href.indexOf("indiachan") != -1){}
			else if (window.location.href.indexOf("2chan") != -1){
				let but = document.querySelector('input[value="返信する"]') || document.querySelector('input[value="スレッドを立てる"]');
				but.parentNode.insertBefore(div,but);
				div.style.display = "inline";
				div.style.zIndex = "5000";
			}
			else {document.body.appendChild(div);}*/
		}
		return butt;
	}
/*	document.querySelectorAll("html,div,iframe,body").forEach( (elem) => {
		if (_isNotIrrelevantInfo(elem)) {
			if (_isContentEditable(elem) && _isDisplayed(elem)) {
				elemId = 'letButton';
				if (document.getElementById(elemId)) {document.getElementById(elemId).remove();div = _createLetButton(elemId, elem, false);document.body.appendChild(div);}
				else {div = _createLetButton(elemId, elem, false);document.body.appendChild(div);}
			}
		}
	});*/
	//return div;
	//return butt;
}
function createResponseWindow() {
	if(responseDiv == undefined || responseDiv == null){
		responseDiv = document.createElement("div");
		responseDiv.setAttribute("class","oracleResponseDiv");
		responseDiv.innerHTML = "awaiting response...";
		responseDiv.setAttribute("style",defaultStyle);
		responseDiv.style.visibility = "hidden";
		document.body.appendChild(responseDiv);
		let close = document.createElement("a");
		close.innerHTML = "[x]";
		close.addEventListener("click",function(event){event.preventDefault();responseDiv.setAttribute("style",defaultStyle);});
		close.setAttribute("style","position:absolute; right:2px;");
		responseDiv.appendChild(close);
	}
}
/*
function _createLetButton(id, sourceElem, includeForm){
	let fldName = _getClassOrNameOrId(sourceElem);
	if (fldName === '') {fldName = '\u00a0';} //&nbsp;
	let style = 'display:block;padding:0 4px;color:#000;opacity:0.9;font:bold 11px sans-serif;text-decoration:none;text-align:center;z-index:2147483647;cursor:default;border:1px solid #000;';
	let compstyle = document.defaultView.getComputedStyle(sourceElem, null);
	let width = 0;
	if ('BODY' !== sourceElem.nodeName && 'HTML' !== sourceElem.nodeName) {width = parseInt(compstyle.getPropertyValue("width").replace('px', ''));} // do need place info about body or html next to (and outside) the element
	let padding = parseInt(compstyle.getPropertyValue("padding-right").replace('px', ''));
	let border = parseInt(compstyle.getPropertyValue("border-right-width").replace('px', ''));
	let left = 0, top = 0, elem = sourceElem;
	let div = document.createElement('div');
	div.setAttribute('id', id);
	div.setAttribute('style', style);
	div.addEventListener("mouseenter", function(){this.style.opacity=1;this.style.zIndex=1002;}, false);
	div.addEventListener("mouseleave", function(){this.style.opacity=0.9;this.style.zIndex=1001;}, false);
	if (elem.offsetParent) {do {left += elem.offsetLeft;top += elem.offsetTop;} while ((elem = elem.offsetParent));}
	style += 'position:absolute; top:' + top + 'px; ';
	style += 'left:' + (left + width + padding + border + 4) + 'px; ';
	return div;
}*/
