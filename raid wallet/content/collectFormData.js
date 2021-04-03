/*
 * Copyright (c) 2018. Stephan Mahieu
 *
 * This file is subject to the terms and conditions defined in
 * file 'LICENSE', which is part of this source code package.
 */
// Also contains parts of showFormData.js. Modified by Sam Porter

// quick reply on 2ch.hk main page not working for now since default event is being prevented. to reply to the thread you have to visit thread page. 
// can be fixed in the future

'use strict';

let eventQueue = [];
let awaitingResponse;
let button = undefined;
let txtNode;

browser.runtime.onConnect.addListener((port) => {
	port.onMessage.addListener((msg) => {
		if (msg.eventType == 'success' && awaitingResponse == true) {port.postMessage({eventType:"ok"});awaitingResponse = null;button.innerHTML = "success";}
		if (msg.eventType == 'failure' && awaitingResponse == true) {
			port.postMessage({eventType:"ok"});awaitingResponse = null;button.innerHTML = "retry";button.disabled = false;txtNode.disabled = false;console.log(msg.message);}
	});
});
// the order has to be from most popular to least popular
let filter = [".4chan.",".4channel.","twitter.com","ylilauta.","komica.","kohlchan.","diochan.","ptchan.","hispachan.","2ch.hk","indiachan.","2chan.","github.com","bitcointalk.org","endchan.","wrongthink.",
"ethereum-magicians.org","forum.openzeppelin.com"];
//----------------------------------------------------------------------------
// EventQueue handling methods
//----------------------------------------------------------------------------

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
	if (theContent.length > 0 && _containsPrintableContent(theContent))  {
		event.value = JSON.stringify(theContent);
		event.last = (new Date()).getTime();
		event.node = null;
		console.log("Send content-event for " + event.id + " to background-script: " + event.value);
		browser.runtime.sendMessage(event);
	}
}

function _containsPrintableContent(value) {return value.replace('&nbsp;','').replace(/[^\x20-\x7E]/g, '').replace(/\s/g,'').length > 0;}

//----------------------------------------------------------------------------
// Event listeners
//----------------------------------------------------------------------------
function onContentChanged(event) {
	let t = event.target;
	let n = t.nodeName.toLowerCase();
	if (_isNotIrrelevantInfo(t)) {
		if ("keyup" === event.type) {if ("input" === n) return;if (! (event.key.length === 1 || ("Backspace" === event.key || "Delete" === event.key || "Enter" === event.key))) return;}
		if ("input" === n && !_isTextInputSubtype(t.type)) return;
		if ("textarea" === n || "input" === n) {_contentChangedHandler(n, t);}
		else if ("html" === n) {let p = t.parentNode;if (p && "on" === p.designMode) {_contentChangedHandler("html", p);}}
		else if ("body" === n || "div" === n) {
			let doc = t.ownerDocument;
			let e = t;
			if (("on" === doc.designMode) || _isContentEditable(e)) {_contentChangedHandler("body" === n ? "iframe" : "div", e);}
		}
	}
}

function _contentChangedHandler(type, node) {
	let location = node.ownerDocument.location;
	console.log("default location is: " + location);
	let nodeFix;
	if (window.location.href.indexOf("4chan") != -1) {
		nodeFix = document.querySelector("#qrForm > div > textarea");
		if(nodeFix) {
			nodeFix.name = "qCom";
			console.log(nodeFix);
			if (nodeFix === node) {
				if (window.location.href.indexOf("thread") == -1) {let qrTid = document.getElementById("qrTid");location = location + "thread/" + qrTid.innerHTML + ".html/";}
			}
		}
	}
	if (window.location.href.indexOf("diochan") != -1 || window.location.href.indexOf("ptchan") != -1) {
		nodeFix = document.querySelector("#quick-reply > div > table > tbody > tr > td > textarea");
		if(nodeFix) {nodeFix.name = "qCom";console.log(nodeFix);}
	}
	if (window.location.href.indexOf("hispachan") != -1) {
		nodeFix = document.querySelector("#quick_reply > table > tbody > tr > td > textarea");
		if(nodeFix) {
			nodeFix.name = "qCom";
			console.log(nodeFix);
			if (nodeFix === node) {
				if (window.location.href.indexOf("res") == -1) {
					let qrTid = document.querySelector(".quick_reply_title");
					let str = qrTid.innerHTML;
					let res = str.substring(18);
					location = location + "res/" + res + ".html/";
				}
			}
		}
	}
	let pagetitle = node.ownerDocument.title;
	let formid = "";
	let id = (node.id) ? node.id : ((node.name) ? node.name : "");
	let name = (node.name) ? node.name : ((node.id) ? node.id : "");
	switch(type) {case "textarea":case "input":formid = _getFormId(node);break;case "html":case "div":case "iframe":break;}
	console.log(name + " was just altered");
	// add to queue (if not already queued)
	if (button) {button.remove();}
	button = findFields(node);
	button.innerHTML = "transact";
	console.log("construction complete");
	button.addEventListener("click", function(clickEvent){
		awaitingResponse = true;
		button.innerHTML = "pending";
		button.disabled = true;
		node.disabled = true;
		txtNode = node;
		button.disabled = true;
		let event = {eventType:1,node:node,type:type,id:id,name:name,formid:formid,url:location.href,host:_getHost(location),pagetitle:pagetitle,
			incognito:browser.extension.inIncognitoContext,last:null,value:null
		};
		if (!_alreadyQueued(event)) {eventQueue.push(event);}
		processEventQueue();
	});
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

function _getElementNameOrId(element) {return (element.name && element.name.length > 0) ? element.name : element.id;}

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
for (let it = 0; it<filter.length;it++) {
	if (window.location.href.indexOf(filter[it]) != -1) {
		document.querySelector("html").addEventListener("keyup", onContentChanged);
		addHandler("input", "change", onContentChanged);
		addHandler("input,textarea", "paste", onContentChanged);
		createDomObserver().observe(document.querySelector("body"),{childList:true,attributes:true,attributeFilter:['contenteditable','designMode','style'],attributeOldValue:true,subtree:true});
		break;
	}
}
//////////////// showFormData.js

function _isNotIrrelevantInfo(node) {
	let name = (node.name) ? node.name : ((node.id) ? node.id : "");
	let irrelevant = ["name","pass","phone","topic","search","sub", "mail","qf-box","find","js-sf-qf","pwd","categ","title","captcha","report","embed","url"];
	let n;
	if (irrelevant.indexOf[name] == -1) {return false;}
	name = node.id;
	if (name) {if (irrelevant.indexOf[name] == -1) {return false;}}
	return true;
}

function findFields(elem) {
	let ii = 0, elemId, div;
	if (_isNotIrrelevantInfo(elem)) {
		if (_isTextInputSubtype(elem.type) && _isDisplayed(elem)) {
			elemId = 'raidButt'+ elem.type + elem.name;
			if (document.getElementById(elemId)) {document.getElementById(elemId).remove();}
			div = _createRaidButton(elemId, elem, true);
			if (window.location.href.indexOf("4chan") != -1 || window.location.href.indexOf("ylilauta") != -1 || window.location.href.indexOf("komica") != -1
			|| window.location.href.indexOf("kohlchan") != -1 || window.location.href.indexOf("diochan") != -1
			|| window.location.href.indexOf("ptchan") != -1 || window.location.href.indexOf("hispachan") != -1) {elem.parentNode.parentNode.appendChild(div);} 
			else if (window.location.href.indexOf("2ch.hk") != -1 || window.location.href.indexOf("adnmb2") != -1
			|| window.location.href.indexOf("indiachan") != -1){elem.parentNode.parentNode.insertBefore(div,elem.parentNode);} 
			else if (window.location.href.indexOf("2chan") != -1){
				let but = document.querySelector('input[value="返信する"]') || document.querySelector('input[value="スレッドを立てる"]');
				but.parentNode.insertBefore(div,but);
				div.style.display = "inline";
				div.style.zIndex = "5000";
			}
			else {document.body.appendChild(div);}
		}
	}
	document.querySelectorAll("html,div,iframe,body").forEach( (elem) => {
		if (_isNotIrrelevantInfo(elem)) {
			if (_isContentEditable(elem) && _isDisplayed(elem)) {
				elemId = 'raidButt';
				if (document.getElementById(elemId)) {document.getElementById(elemId).remove();div = _createRaidButton(elemId, elem, false);document.body.appendChild(div);}
				else {div = _createRaidButton(elemId, elem, false);document.body.appendChild(div);}
			}
		}
	});
	return div;
}

function _createRaidButton(id, sourceElem, includeForm){
	let fldName = _getElementNameOrId(sourceElem);
	if (fldName === '') {fldName = '\u00a0';} //&nbsp;
	let style = 'display:block;padding:0 4px;color:#000;opacity:0.9;font:bold 11px sans-serif;text-decoration:none;text-align:center;z-index:2147483647;cursor:default;';
	let compstyle = document.defaultView.getComputedStyle(sourceElem, null);
	let width = 0;
	if ('BODY' !== sourceElem.nodeName && 'HTML' !== sourceElem.nodeName) {width = parseInt(compstyle.getPropertyValue("width").replace('px', ''));} // do need place info about body or html next to (and outside) the element
	let padding = parseInt(compstyle.getPropertyValue("padding-right").replace('px', ''));
	let border = parseInt(compstyle.getPropertyValue("border-right-width").replace('px', ''));
	let left = 0, top = 0, elem = sourceElem;
	let div = document.createElement('button');
	div.setAttribute('id', id);
	div.setAttribute('style', style);
	div.setAttribute('contenteditable', 'false');
	div.addEventListener("mouseenter", function(){this.style.opacity=1;this.style.zIndex=1002;}, false);
	div.addEventListener("mouseleave", function(){this.style.opacity=0.9;this.style.zIndex=1001;}, false);
	div.appendChild(document.createTextNode(fldName));
	if (elem.offsetParent) {do {left += elem.offsetLeft;top += elem.offsetTop;} while ((elem = elem.offsetParent));}
	style += 'position:absolute; top:' + top + 'px; ';
	style += 'left:' + (left + width + padding + border + 4) + 'px; ';
	return div;
}
