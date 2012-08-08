logger = new Util.Logger("Life::IMAP","debug");
function log(s) {
  logger.debug(s);
}

function SslImapClient() {
    this.clearState();
}

/**
 * @interface
 */
function ImapCommandHandler() {}
/**
 * @param {Array.<String>} reply
 */
ImapCommandHandler.prototype.onUntagged = function(reply) {};
/**
 * @param {Array.<String>} reply
 */
ImapCommandHandler.prototype.onResponse = function(reply) {};

SslImapClient.prototype.clearState = function() {
    this.server = undefined;
    this.email = undefined;
    this.username = undefined;
    this.password = undefined;
    this.socket = undefined;
    this.on_login = undefined;
    this.on_bad_password = undefined;
    this.on_disconnect = undefined;
    this.commands = undefined;
    this.pending_commands = undefined;
    this.response_data = undefined;
    this.next_command_id = undefined;
    this.current_reply = undefined;
    this.data_bytes_needed = undefined;
    this.current_folder = undefined;
    this.idling = undefined;
    this.uid_next = undefined;
    this.fully_connected = undefined;
    this.logging = undefined;
    this.capabilities = undefined;
    
};
SslImapClient.prototype.hasCapability = function(cap) {
    return this.capabilities[cap] == true;
}
SslImapClient.prototype.connect = function(server, email, password, on_login, on_bad_password, on_error, on_disconnect, logging) {
    if(this.socket) 
        throw "already connected";
    this.clearState();
    this.server = server;
    this.username = email.split('@', 1)[0];
    this.email = email;
    this.password = password;
    this.logging = logging;
    this.capabilities = {}

    this.socket = new Socket();
    try {
        this.socket.open(server, 993, "ssl", bind(this.onConnect, this));
        var client = this;
        window.setTimeout(function() {
            if(!client.fully_connected) {
                client.on_disconnect = undefined;
                client.disconnect();
                on_error("Unable to contact server! Check you server settings.");
            }
        }, 15000);
    } catch(err) {
        on_error(err)
    } 
    this.on_login = on_login;
    this.on_bad_password = on_bad_password;
    this.on_disconnect = on_disconnect;
    this.commands = [];
    this.next_command_id = 1;
    this.pending_commands = {};
    this.response_data = "";
    this.current_reply = [""];
    this.data_bytes_needed = undefined;
    this.current_folder = undefined;
    this.idling = false;
    this.uid_next = {};
    this.pending_commands["*"] = {"handler":bind(this.onAckConnect, this), "untagged":function(){}};
};
SslImapClient.prototype.onAckConnect = function(reply) {
    this.fully_connected = true;
    // alert("Initial Hello\n" + response + "\n" + extra);
    var client = this;
    var u = encode_utf8(this.username.replace("\\", "\\\\").replace("\"", "\\\""));
    var p = encode_utf8(this.password);
    //this.sendCommand('LOGIN \"' + u + '\" \"' + p + "\"", bind(this.onLogin, this), function() {});
    // var auth = btoa("\0" + u + "\0" + p);
    // this.sendCommand('AUTHENTICATE PLAIN',bind(this.onLogin, this), function() {}, true, 
    //     function() {
    //         if(client.logging)
    //             log("IMAP OUT @ " + new Date() + ":\n" + auth);
    //         client.socket.write(auth + "\r\n");
    //     }
    // );
    this.sendCommand('LOGIN \"' + u + '\" {' + p.length + '}',bind(this.onLogin, this), function() {}, true, 
        function() {
            if(client.logging)
                log("--> " + p);
            client.socket.write(p + "\r\n");
        }
    );
};
SslImapClient.prototype.onLogin = function(reply) {
    var reply = reply[0].split(" ", 1);
    var client = this;
    if(reply == "OK") {
        this.sendCommand("CAPABILITY", 
            function() {
                client.on_login();
            }, 
            function(reply) {
                var parts = reply[0].split(" ");
                if(parts[0] == "CAPABILITY") {
                    parts.shift();
                    for(var i = 0; i < parts.length; ++i) {
                        client.capabilities[parts[i]] = true;
                    }
                }
            }
        );
    } else {
        this.on_disconnect = undefined;
        this.on_bad_password();
        this.disconnect();
    }
};
/*
 * @constructor
 */
function ImapListHandler(since_uid, next_uid, on_success, on_error) {
    this.results = [];
    this.since_uid = since_uid;
    this.next_uid = next_uid;
    this.on_success = on_success;
    this.on_error = on_error;
};
/**
 * @param {Array.<String>} reply
 */
ImapListHandler.prototype.onUntagged = function(reply) {
    if(reply[0].split(" ")[0] != "SEARCH")
        return;
    this.results = reply[0].split(" ");
    this.results.shift();
    if(this.results[this.results.length - 1] == "")
        this.results.pop();
    for(var i = 0; i < this.results.length; ++i) {
        this.results[i] = parseInt(this.results[i]);
    }
};
/**
 * @param {Array.<String>} reply
 */
ImapListHandler.prototype.onResponse = function(reply) {
    if(reply[0].split(" ", 1) != "OK") {
        this.on_error(reply[0]);
    } else {
        if(!this.next_uid) {
            for(var i = 0; i < this.results.length; ++i) {
                if(!this.next_uid || this.results[i] > this.next_uid)
                    this.next_uid = this.results[i] + 1;
                if(this.results[i] < this.since_uid) {
                    this.results.splice(i, 1);
                }
            }
        }
        this.on_success(this.results, this.next_uid);
    }
};
// var month_short_names = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
/**
 * @param {string} folder
 * @param {string} tag
 * @param {number} after_uid
 * @param {Date} since_date
 * @param {function(Array.<number>, number)} on_success
 * @param {function(string)} on_error
 */
SslImapClient.prototype.listMessages = function(folder, tag, since_uid, life, on_success, on_error) {
    if(tag == undefined)
        tag = "[Life][";
    else
        tag = "[Life][" + tag + "]";
    var client = this;
    var next_uid = undefined;
    //you have to issue a select before search or the IMAP server may return a cached set of results (atleast GMAIL does)
    this.sendCommand("SELECT \"" + folder + "\"", function(reply) {
        //alert("got select");
        if(reply[0].split(" ", 1) != "OK") {
            on_error(reply[0]);
        } else {
            client.current_folder = folder;
            if(next_uid && since_uid && since_uid >= next_uid) {
                on_success([], next_uid);
                return;
            }
            var handler = new ImapListHandler(since_uid, next_uid, on_success, on_error);
            // if(since_date) {
            //     since_date = " SENTSINCE " + since_date.getDate() + "-" + month_short_names[since_date.getMonth()] + "-" + since_date.getFullYear();
            // } else {
            //     since_date = "";
            // }
            if(since_uid) {
                since_uid = " UID " + since_uid + ":*";
            } else {
                since_uid = "";
            }
            if(life)
                life = " SUBJECT \"" + tag + "\" HEADER \"X-LIFE\" \"\"";
            else 
                life = "";
            client.sendCommand("UID SEARCH" + since_uid + " NOT DELETED" + life, bind(handler.onResponse, handler), bind(handler.onUntagged, handler), true);
        }
    }, function(reply) {
        if(reply[0].indexOf("UIDNEXT") != -1) {
            next_uid = parseInt(reply[0].split("UIDNEXT ", 2)[1].split("]")[0]);
        } 
    });
};
/*
 * @constructor
 */
function ImapOpenOrCreateHandler(client, folder, on_success, on_error) {
    this.on_success = on_success;
    this.on_error = on_error;
    this.folder = folder;
    this.client = client;
};
/**
 * @param {Array.<String>} reply
 */
ImapOpenOrCreateHandler.prototype.onUntagged = function(reply) {
};
/**
 * @param {Array.<String>} reply
 */
ImapOpenOrCreateHandler.prototype.onCreateResponse = function(reply) {
    this.client.sendCommand("SELECT \"" + this.folder + "\"", bind(this.onSelectResponse, this), bind(this.onUntagged, this), true);
};
/**
 * @param {Array.<String>} reply
 */
ImapOpenOrCreateHandler.prototype.onSelectResponse = function(reply) {
    if(reply[0].split(" ", 1) != "OK") {
        this.on_error(reply[0]);
    } else {
        this.client.current_folder = this.folder;
        this.on_success();
    }
};
SslImapClient.prototype.openOrCreateFolder = function(folder, on_success, on_error) {
    var handler = new ImapOpenOrCreateHandler(this, folder, on_success, on_error);
    this.sendCommand("CREATE " + folder, bind(handler.onCreateResponse, handler), bind(handler.onUntagged, handler), false);
};

/*
 * @constructor
 */
function ImapCreateHandler(on_success, on_error) {
    this.on_success = on_success;
    this.on_error = on_error;
};
/**
 * @param {Array.<String>} reply
 */
ImapCreateHandler.prototype.onUntagged = function(reply) {
};
/**
 * @param {Array.<String>} reply
 */
ImapCreateHandler.prototype.onResponse = function(reply) {
    if(reply[0].split(" ", 1) != "OK") {
        this.on_error(reply[0]);
    } else {
        this.on_success(this.messages);
    }
};
/**
 * @param {string} folder
 * @param {function()} on_success
 * @param {function(string)} on_error
 */
SslImapClient.prototype.createFolder = function(folder, on_success, on_error) {
    var handler = new ImapCreateHandler(on_success, on_error);
    this.sendCommand("CREATE " + folder, bind(handler.onResponse, handler), bind(handler.onUntagged, handler), false);
}
/*
 * @constructor
 */
function ImapCopyHandler(on_success, on_error) {
    this.on_success = on_success;
    this.on_error = on_error;
};
/**
 * @param {Array.<String>} reply
 */
ImapCopyHandler.prototype.onUntagged = function(reply) {
};
/**
 * @param {Array.<String>} reply
 */
ImapCopyHandler.prototype.onResponse = function(reply) {
    if(reply[0].split(" ", 1) != "OK") {
        this.on_error(reply[0]);
    } else {
        this.on_success(this.messages);
    }
};
/**
 * @param {string} to
 * @param {string} from
 * @param {number} uid
 * @param {function()} on_success
 * @param {function(string)} on_error
 */
SslImapClient.prototype.copyMessage = function(to, from, uid, on_success, on_error) {
    if(typeof(uid) == "Array")
        uid = uid.join(",");
    var client = this;
    if(this.current_folder != from) {
        this.sendCommand("SELECT \"" + folder + "\"", function(reply) {
            //alert("got select");
            if(reply[0].split(" ", 1) != "OK") {
                on_error(reply[0]);
            } else {
                client.current_folder = from;
                var handler = new ImapCopyHandler(on_success, on_error);
                client.sendCommand("UID COPY " + uid + " " + to, bind(handler.onResponse, handler), bind(handler.onUntagged, handler), true);
            }
        }, function() {});
    } else {
        var handler = new ImapCopyHandler(on_success, on_error);
        client.sendCommand("UID COPY " + uid + " " + to, bind(handler.onResponse, handler), bind(handler.onUntagged, handler), false);
    }
}
/*
 * @constructor
 */
function ImapDeleteHandler(client, uid, on_success, on_error) {
    this.client = client;
    this.on_success = on_success;
    this.on_error = on_error;
    this.uid = uid;
};
/**
 * @param {Array.<String>} reply
 */
ImapDeleteHandler.prototype.onUntagged = function(reply) {
};
/**
 * @param {Array.<String>} reply
 */
ImapDeleteHandler.prototype.onResponse = function(reply) {
    if(reply[0].split(" ", 1) != "OK") {
        this.on_error(reply[0]);
    } else {
        //we don't need to wait for the expunge
        if(!this.client.hasCapability("UIDPLUS")) {
            this.client.sendCommand("EXPUNGE", function() {}, function() {}, true);
        } else {
            this.client.sendCommand("UID EXPUNGE " + this.uid, function() {}, function() {}, true);
        }
        this.on_success(this.messages);
    }
};
/**
 * @param {string} to
 * @param {string} from
 * @param {number} uid
 * @param {function()} on_success
 * @param {function(string)} on_error
 */
SslImapClient.prototype.deleteMessage = function(folder, uid, on_success, on_error) {
    if(typeof(uid) == "Array")
        uid = uid.join(",");
    var client = this;
    if(this.current_folder != folder) {
        this.sendCommand("SELECT \"" + folder + "\"", function(reply) {
            //alert("got select");
            if(reply[0].split(" ", 1) != "OK") {
                on_error(reply[0]);
            } else {
                client.current_folder = folder;
                var handler = new ImapDeleteHandler(client, uid, on_success, on_error);
                client.sendCommand("UID STORE " + uid + " +FLAGS (\\Deleted)", bind(handler.onResponse, handler), bind(handler.onUntagged, handler), true);
            }
        }, function() {});
    } else {
        var handler = new ImapDeleteHandler(client, uid, on_success, on_error);
        client.sendCommand("UID STORE " + uid + " +FLAGS (\\Deleted)", bind(handler.onResponse, handler), bind(handler.onUntagged, handler), false);
    }
}


//TODO: is this according to the RFC
function extractMailAddressRFC(raw) {
    var lt = raw.indexOf('<');
    if(lt != -1) {
        var gt = raw.indexOf('>');
        raw = raw.slice(lt + 1, gt);
    }
    return raw.trim();
}

var message_tokenizer = /\(|\)|\\?[\w\d]+(?:\[[^\]]*\])?|\s+|(?:"(?:[^"\\]|\\.)*")|\{\d*\}/g;

function tokenizeMessage(msg) {
    var match;
    var tokens = [];
    var levels = [tokens];
    message_tokenizer.lastIndex = 0;
    do {
        // log(JSON.stringify(levels));
        var last_index = message_tokenizer.lastIndex;
        match = message_tokenizer.exec(msg);
        //invalid message
        if(!match || last_index + match[0].length != message_tokenizer.lastIndex) {
            // log("skipped @\n" + msg.slice(last_index));
            return undefined;
        }
        if(match[0] == "(") {
            levels.push([]);
            levels[levels.length - 2].push(levels[levels.length - 1]);
        } else if(match[0] == ")") {
            levels.pop();
            if(levels.length == 0) {
                // log("too many )");
                return undefined;
            }
        } else if(!(/^\s+$/.test(match[0]))) {
            levels[levels.length - 1].push(match[0]);
        }
    } while(message_tokenizer.lastIndex != msg.length);
    if(message_tokenizer.lastIndex != msg.length) {
        // log("missed end");
        return undefined;
    }
    return tokens;
}

function mimeBodyStructure(parts) {
    var mime = [];
    if((typeof parts[0]) == "object") {
        for(var i = 0; i < parts.length; ++i) {
            if((typeof parts[i]) == "object")
                mime.push(mimeBodyStructure(parts[i]));
            else
                break;
        }
        return mime;
    }
    return (parts[0].slice(1, parts[0].length - 1) + "/" + parts[1].slice(1, parts[1].length - 1)).toLowerCase();
}

function partsOfType(parts, type) {
    var jsons = [];
    for(var i = 0; i < parts.length; ++i) {
        if(parts[i]  == type) {
            jsons.push("" + (i + 1))
            continue;
        }
        if(typeof parts[i]  != "object")
            continue;
        var p = partsOfType(parts[i], type);
        if(!p)
            continue;
        for(var j = 0; j < p.length; ++j)
            jsons.push("" + (i + 1) + "." + p[j]);
    }
    if(jsons.length == 0)
        return undefined;
    return jsons;
}

/*
 * @constructor
 */
function LifeMessage() {
    this.id = undefined;
    this.uid = undefined;
    this.from = undefined;
    this.to = undefined;
    this.date = undefined;
    this.tag = undefined;
    this.subject= undefined;
    this.txt=undefined;
    this.html=undefined;
    this.base64= undefined;
    this.crypted= undefined;
    this.structure= undefined;
}

/*
 * @constructor
 */
function ImapFetchLifeHandler(client, on_success, on_error) {
    this.structures = {};
    this.messages = {};
    this.finished_messages = [];
    this.finished_message_ids = [];
    this.client = client;
    this.on_success = on_success;
    this.on_error = on_error;
};
var whitespace_start_regex = /^\s+/;
/**
 * @param {Array.<String>} reply
 */
ImapFetchLifeHandler.prototype.onUntagged = function(reply) {
    if(reply.length < 2) {
        //this means a header was not returned
        return;
    }
    //TODO: other checks like split(" ")[1] == "FETCH"?
    //TODO: does imap always return them in our requested order?
    var msg = new LifeMessage();
    msg.uid = parseInt(reply[0].split("UID ", 2)[1].split(" ", 1)[0]);
    var headers = reply[1].split("\r\n");
    for(var i = 0; i < headers.length; ++i) {
        var header = headers[i];
        while(i + 1 < headers.length && whitespace_start_regex.test(headers[i + 1])) {
            var whitespace = whitespace_start_regex.exec(headers[i + 1]);
            header += " " + headers[i + 1].slice(whitespace.length);
            ++i;
        }
        var colon = header.indexOf(":");
        var key = header.slice(0, colon);
        key = key.toLowerCase(); // name will only be lower case
        var value = header.slice(colon + 2); //skip ": "
        switch(key) {
        case "message-id":
            msg.id = value;
            break;
        case "subject":
            var tag_part = /\[Life\]\[([^\]]+)\] (.*)$/.exec(value);
            if(tag_part) {
                msg.tag = tag_part[1];
                msg.subject = tag_part[2];
            } else {
                log("Bad subject for Life:\n" + value + "\n" + JSON.stringify(headers));
            }
            break;
        case "date":
            msg.date = new Date(value);
            break;
        case "from":
            msg.from = extractMailAddressRFC(value);
            break;
        case "to":
            msg.to = value.split(",");
            for(var j = 0; j < msg.to.length; ++j) {
                msg.to[j] = extractMailAddressRFC(msg.to[j]);
            }
            break;
        }
        
    } 
    if(!msg.uid || !msg.tag || !msg.date || !msg.from || !msg.to) {
        return;
    }
    var parts = tokenizeMessage(reply[0]);
    if(!parts) {
        log("failed to parse " + msg.uid + "\n" + reply[0]);
        return;
    }

    parts = parts[2];
    for(var i = 0; i < parts.length - 1; ++i) {
        if(parts[i] == "BODYSTRUCTURE") {
            msg.structure = mimeBodyStructure(parts[i + 1]);
            var s = JSON.stringify(msg.structure);
            if(!(s in this.structures)) {
                this.structures[s] = [];
            }
            this.structures[s].push(msg.uid);
            this.messages[msg.uid] = msg;
            return;
        }
    }
};
ImapFetchLifeHandler.prototype.onUntaggedBody = function(reply) {
    var uid = parseInt(reply[0].split("UID ", 2)[1].split(" ", 1)[0]);
    var msg = this.messages[uid];
    if(msg == undefined) {
        log("unknown uid returned " + uid);
        return;
    }

    if(reply.length < 2) {
        log("missing body for uid " + uid);
        //this means a body was not returned
        delete this.messages[uid];
        return;
    }
    try {
        // hack!
        msg.crypted = (partsOfType(msg.structure, "application/pgp-encrypted") != undefined);
        msg.base64=reply[1].replace(/[\r\n]/g, "");
        this.finished_messages.push(msg);
        this.finished_message_ids.push(msg.uid);
    } catch (err) {
        delete this.messages[uid];
    }
}
/**
 * @param {Array.<String>} reply
 */
ImapFetchLifeHandler.prototype.onResponse = function(reply) {
    if(reply[0].split(" ", 1) != "OK") {
        this.on_error(reply[0]);
    } else {
        for(var s in this.structures) {
            log("" + this.structures[s].length + " messages of type\n" + s);
            var example_msg_uid = this.structures[s][0];
            var st = this.messages[example_msg_uid].structure;
            var uid = "" + this.structures[s].join(",");
            var part = partsOfType(st, "application/json") || partsOfType(st, "application/pgp-encrypted");
            if(!part)
                continue;
            this.client.sendCommand("UID FETCH " + uid + " (BODY.PEEK[" + part.join("] BODY.PEEK[") + "])", bind(this.onResponse, this), bind(this.onUntaggedBody, this), true);
            delete this.structures[s];
            return;
        }

        this.on_success(this.finished_messages, this.finished_message_ids);
    }
};    

/**
 * @param {string} folder
 * @param {number} uid
 * @param {function(Array.<LifeMessage>)} on_success
 * msgid, tag, date, from, to, obj
 * @param {function(string)} on_error
 */
SslImapClient.prototype.getLifeMessage = function(folder, uid, on_success, on_error) {
    if(typeof(uid) == "Array")
        uid = uid.join(",");
    var client = this;
    //TODO: can we assume that a mime forwarding mailing list will always make our message MIME part one.
    //This code assumes the JSON is either part 2 or 1.2 and relies on the server to return an inline nil for the missing part
    if(this.current_folder != folder) {
        this.sendCommand("SELECT \"" + folder + "\"", function(reply) {
            //alert("got select");
            if(reply[0].split(" ", 1) != "OK") {
                on_error(reply[0]);
            } else {
                client.current_folder = folder;
                var handler = new ImapFetchLifeHandler(client, on_success, on_error);
                client.sendCommand("UID FETCH " + uid + " (BODY.PEEK[HEADER.FIELDS (MESSAGE-ID IN-REPLY-TO DATE FROM TO SUBJECT)] BODYSTRUCTURE)", bind(handler.onResponse, handler), bind(handler.onUntagged, handler), true);
            }
        }, function() {});
    } else {
        var handler = new ImapFetchLifeHandler(client, on_success, on_error);
        client.sendCommand("UID FETCH " + uid + " (BODY.PEEK[HEADER.FIELDS (MESSAGE-ID IN-REPLY-TO DATE FROM TO SUBJECT)] BODYSTRUCTURE)", bind(handler.onResponse, handler), bind(handler.onUntagged, handler), false);
    }
};

/**
 * @param {string} folder
 */
SslImapClient.prototype.waitMessages = function(folder, expected_next_uid, on_success, on_error) {
    var client = this;
    var cancel_idle = false;
    var exists = undefined;
    this.sendCommand("SELECT \"" + folder + "\"", 
        function(reply) {
            //alert("got select");
            if(reply[0].split(" ", 1) != "OK") {
                on_error(reply[0]);
            } else {
                client.current_folder = folder;
                if(cancel_idle) {
                    on_success();
                    return;
                }
                client.sendCommand("IDLE", 
                    function(reply) { 
                        client.idling = false; 
                        if(reply[0].split(" ", 1) != "OK") {
                            on_error(reply[0]);
                        } else {
                            on_success();
                        }
                    }, function(reply) { 
                        if(reply[0].indexOf("EXISTS") != -1) {
                            var new_exists = parseInt(reply[0].split(" ", 1)[0]);
                            if(exists != new_exists) {
                                // alert("exists changed, idle satisfied");
                                cancel_idle = true;
                            }
                            if(client.idling) {
                                this.idling = false;
                                if(this.logging)
                                    log("--> DONE Reason: cancel after continuation response");
                                client.socket.write("DONE\r\n");
                            }
                        } 
                    }, true, function() { 
                        if(!cancel_idle)
                            client.idling = true;
                        else {
                            this.idling = false;
                            if(this.logging)
                                log("--> DONE Reason: cancel idle on continuation response");
                            client.socket.write("DONE\r\n");
                        }
                        
                    }
                );
            }
        }, function(reply) {
            if(reply[0].indexOf("UIDNEXT") != -1) {
                var next_uid = parseInt(reply[0].split("UIDNEXT ", 2)[1].split("]")[0]);
                if(expected_next_uid == undefined) {
                    expected_next_uid = next_uid;
                    alert("assuming wait for any new message could lose data" + expected_next_uid);
                } else {
                    if(next_uid > expected_next_uid)
                        cancel_idle = true;
                }
            } 
            if(reply[0].indexOf("EXISTS") != -1) {
                exists = parseInt(reply[0].split(" ", 1)[0]);
            } 
        }
    );
};
SslImapClient.prototype.sendCommand = function(command, on_response, on_untagged, continuation, on_continue) {
    if(on_untagged == undefined)
        on_untagged = function(reply) { alert("untagged\n" + reply); };
    if(on_continue == undefined)
        on_continue = function(reply) { alert("continue\n" + reply); };
    if(!continuation)
        this.commands.push({"command":command, "handler":on_response, "untagged": on_untagged, "continue": on_continue});
    else
        this.commands.unshift({"command":command, "handler":on_response, "untagged": on_untagged, "continue": on_continue});
    this.internalNextCommand();
};
SslImapClient.prototype.internalNextCommand = function() {
    if(!this.idling) {
        for(var id in this.pending_commands) {
            //bail out if there are pending commands
            return;
        }
    }
    if(this.commands.length == 0)
        return;
    if(this.idling && this.commands[0]["command"] != "DONE") {
        //cancel the idle
        this.idling = false;
        if(this.logging)
            log("--> DONE Reason: cancel because new command was issued: " + JSON.stringify(this.commands[0]));
        this.socket.write("DONE\r\n");
        return;
    }
    var cmd = this.commands.shift();
    var id = "Ax" + this.next_command_id++;
    cmd["id"] = id;
    var data_bit = id + " " + cmd["command"] + "\r\n";
    if(this.logging)
        log("--> " + data_bit);
    this.socket.write(data_bit);
    this.pending_commands[id] = cmd;
};
SslImapClient.prototype.disconnect = function() {
    if(this.socket == undefined)
        return;
    this.socket.close();
    this.socket = undefined;
};
SslImapClient.prototype.onConnect = function() {
    // alert('connected');
    var client = this;
    var socket_cbs = {
        "streamStarted": function (socketContext){ 
            //do nothing, this just means data came in... we'll
            //get it via the receiveData callback
        },
        "streamStopped": function (socketContext, status){ 
            client.onDisconnect();
        },
        "receiveData":   function (data){
            client.onData(data);
        }
    };
    this.socket.async(socket_cbs);
    this.internalNextCommand();
};
SslImapClient.prototype.onDisconnect = function() {
    if(this.socket) {
        this.socket.close();
        this.socket = undefined;
    }
    if(this.on_disconnect)
        this.on_disconnect();
};
SslImapClient.prototype.onData = function(data) {
    if(this.logging)
        log("<-- " + data);
    this.response_data += data;
    for(;;) {
        if(this.data_bytes_needed) {
            if(this.response_data.length < this.data_bytes_needed)
                return;
            this.current_reply.push(this.response_data.slice(0, this.data_bytes_needed));
            this.response_data = this.response_data.slice(this.data_bytes_needed);
            this.data_bytes_needed = undefined;
            //ok, now we wait for the actual command to complete
            continue;
        }
        var ofs = this.response_data.indexOf('\n');
        //not complete
        if(ofs == -1)
            return;
        var partial = this.response_data.slice(0, ofs - 1);
        var literal_end = partial.lastIndexOf('}');
        if(literal_end == ofs - 2) {
            var literal_start = partial.lastIndexOf('{');
            this.data_bytes_needed = parseInt(partial.slice(literal_start + 1, literal_end));
            this.current_reply[0] += partial.slice(0, literal_start) + "{}";
            this.response_data = this.response_data.slice(ofs + 1);
            //ok now we need the literal
            continue;
        } else {
            this.current_reply[0] += partial;
            this.response_data = this.response_data.slice(ofs + 1);
        }
        var cmd = this.current_reply[0].split(" ", 1)[0];
        this.current_reply[0] = this.current_reply[0].slice(cmd.length + 1);
        if(!(cmd in this.pending_commands)) {
            if(cmd == "*") {
                for(var i in this.pending_commands) {
                    this.pending_commands[i]["untagged"](this.current_reply);
                }
            } else if(cmd == "+") {
                for(var i in this.pending_commands) {
                    this.pending_commands[i]["continue"](this.current_reply);
                }
            } else {
                alert("unknown cmd " + cmd + " " + this.current_reply);
            }
        } else {
            this.pending_commands[cmd]["handler"](this.current_reply);
            delete this.pending_commands[cmd];
        }
        this.current_reply = [""];
        this.internalNextCommand();
    }
};

function SslSmtpClient() {
    this.clearState();
};
SslSmtpClient.prototype.clearState = function() {
    this.server = undefined;
    this.username = undefined;
    this.email = undefined;
    this.password = undefined;
    this.socket = undefined;
    this.on_login = undefined;
    this.on_bad_password = undefined;
    this.on_disconnect = undefined;
    this.commands = undefined;
    this.pending_command = undefined;
    this.response_data = undefined;
    this.current_reply = undefined;
    this.fully_connected = undefined;
    this.logging = undefined;
};
SslSmtpClient.prototype.connect = function(server, email, password, on_login, on_bad_password, on_error, on_disconnect, logging) {
    if(this.socket) 
        throw "already connected";
    this.clearState();
    this.server = server;
    this.username = email.split('@', 1)[0];
    this.email = email;
    this.password = password;
    this.logging = logging;

    this.socket = new Socket();
    try {
        this.socket.open(server, 465, "ssl", bind(this.onConnect, this));
        var client = this;
        window.setTimeout(function() {
            if(!client.fully_connected) {
                client.on_disconnect = undefined;
                client.disconnect();
                on_error("Unable to contact server! Check you server settings.");
            }
        }, 15000);
    } catch(err) {
        on_error(err);
        return;
    }
    this.on_login = on_login;
    this.on_bad_password = on_bad_password;
    this.on_disconnect = on_disconnect;
    this.commands = []
    this.response_data = "";
    this.current_reply = [];
    this.pending_command = bind(this.onAckConnect, this);
};
SslSmtpClient.prototype.onAckConnect = function(reply) {
    this.fully_connected = true;
    this.sendCommand('EHLO somehost', bind(this.onShake, this));
};
SslSmtpClient.prototype.onShake = function(reply) {
    // alert("on shake");
    var u = encode_utf8(this.username);
    var p = encode_utf8(this.password);
    var auth = btoa("\0" + u + "\0" + p);
    this.sendCommand("AUTH PLAIN " + auth, bind(this.onLogin, this));
};
SslSmtpClient.prototype.sendMessage = function(msg, on_success, on_error) {
    log("sendMessage: msg=" + msg.toSource());
    if(!this.fully_connected) {
        on_error("SMTP is not fully connected");
        return;
    }
    if(msg.to.length < 1)
        throw "at least one destination email is required";
    var data = "";

    data += "X-Life: " + msg.tag + "\r\n";
    
    data += "MIME-Version: 1.0\r\n";
    data += "To:";
    for(var i = 0; i < msg.to.length - 1; ++i) {
        data += " " + encode_utf8(msg.to[i]) + ",";
    }
    data += " " + msg.to[msg.to.length - 1] + "\r\n";

    data += "From: " + encode_utf8(this.email) + "\r\n";
    data += "Subject: [Life][" + msg.tag + "] " + encode_utf8(msg.subject) + "\r\n";
    
    var divider = "------------xxxxxxxxxxxxxxxxxxxxxxxx".replace(/x/g, function(c) { return (Math.random()*16|0).toString(10); });
    
    data += "Content-Type: multipart/mixed; boundary=\"" + divider + "\"\r\n";
    data += "\r\n";
    data += "This is a multi-part message in MIME format.\r\n";
    
    ///////////
    if(msg.txt) {
      data += "--" + divider + "\r\n";
      data += "Content-Type: text/plain; charset=\"utf-8\"\r\n"
      data += "Content-Transfer-Encoding: 8bit\r\n";
      data += "\r\n";
      data += encode_utf8(msg.txt.replace(/(^|[^\r])(?=\n)/g, function(c) { return c + "\r"; }));
      data += "\r\n";
    }

    ///////////
    if(msg.html) {
      data += "--" + divider + "\r\n";
      data += "Content-Type: text/html; charset=\"utf-8\"\r\n"
      data += "Content-Transfer-Encoding: 8bit\r\n";
      data += "\r\n";        
      data += encode_utf8(msg.html.replace(/(^|[^\r])(?=\n)/g, function(c) { return c + "\r"; }));
      data += "\r\n";
    }

    ///////////
    if(msg.base64) {
      data += "--" + divider + "\r\n";
      if(msg.crypted)
        data += "Content-Type: application/pgp-encrypted; charset=\"us-ascii\"\r\n"
      else
        data += "Content-Type: application/json; charset=\"us-ascii\"\r\n"
      data += "Content-Transfer-Encoding: base64\r\n";
      data += "\r\n";
      var encoded = msg.base64;
      for(var i = 0; i < encoded.length; i += 74) {
          data += encoded.slice(i, i + 74) + "\r\n";
      }
    }
    data += "--" + divider + "--\r\n";
    data += ".";
    
    var send_cmd = {"to":msg.to.slice(0), "data":data, "success":on_success, "error":on_error};
    log("send_cmd/start" + send_cmd.toSource());
    var client = this;
    client.sendCommand("MAIL FROM: <" + this.email + "> BODY=8BITMIME", function(reply) {
        log("send_cmd/cont" + send_cmd.toSource());
        var code = reply[0].split(" ", 1);
        if(code != "250" && code != "354") {
            send_cmd["error"](reply.join("\n"));
            return;
        }
        if(send_cmd.to && send_cmd.to.length > 0) {
            //send recipients 1 by 1
            client.sendCommand("RCPT TO: <" + send_cmd.to.pop() + ">", arguments.callee, true, on_error);
        } else if(send_cmd.to) {
            //then send the data message
            delete send_cmd["to"];
            log("send_cmd/cont/delete" + send_cmd.toSource());
            client.sendCommand("DATA", arguments.callee, true, on_error);
        } else if("data" in send_cmd){
            //then send actual data
            var data = send_cmd["data"];
            delete send_cmd["data"];
            client.sendCommand(data, arguments.callee, true, on_error)
        } else {
            send_cmd["success"]();
        }
    }, false, on_error);
    
};
SslSmtpClient.prototype.onLogin = function(reply) {
    var code = reply[0].split(" ", 1);
    if(code == "235") {
        this.on_login();
    } else {
        this.on_disconnect = undefined;
        this.on_bad_password();
        this.disconnect();
    }
};
SslSmtpClient.prototype.sendCommand = function(command, on_response, continuation, on_error) {
    try{
      if(!continuation)
          this.commands.push({"command":command, "handler":on_response});
      else 
          this.commands.unshift({"command":command, "handler":on_response});
      this.internalNextCommand();
    }
    catch(e) {
      on_error(e);
    }
};
SslSmtpClient.prototype.internalNextCommand = function() {
    if(this.pending_command)
        return;
    if(this.commands.length == 0)
        return;
    var cmd = this.commands.shift();
    var data_bit = cmd["command"] + "\r\n";
    if(this.logging)
        log("SMTP --> " + data_bit);
    this.socket.write(data_bit);
    this.pending_command = cmd["handler"];
};
SslSmtpClient.prototype.disconnect = function() {
    if(this.socket == undefined)
        return;
    this.socket.close();
    this.socket = undefined;
};
SslSmtpClient.prototype.onConnect = function() {
    // alert('connected');
    var client = this;
    var socket_cbs = {
        "streamStarted": function (socketContext){ 
            //do nothing, this just means data came in... we'll
            //get it via the receiveData callback
        },
        "streamStopped": function (socketContext, status){ 
            client.onDisconnect();
        },
        "receiveData":   function (data){
            client.onData(data);
        }
    };
    this.socket.async(socket_cbs);
    this.internalNextCommand();
};
SslSmtpClient.prototype.onDisconnect = function() {
    if(this.socket) {
        this.socket.close();
        this.socket = undefined;
    }
    if(this.on_disconnect)
        this.on_disconnect();
};
SslSmtpClient.prototype.onData = function(data) {
    if(this.logging)
        log("SMTP <-- " + data);
    this.response_data += data;
    for(;;) {
        var ofs = this.response_data.indexOf('\n');
        //not complete
        if(ofs == -1) {
            // alert("bailing\n" + this.response_data);
            return;
        }
        //TODO: handle gibbrish respone (not a 3 dig number with a space or - after it)
        var reply = this.response_data.slice(0, ofs - 1);
        this.response_data = this.response_data.slice(ofs + 1);
        this.current_reply.push(reply);
        // alert("adding\n" + reply);
        if(reply[3] == "-")
            continue;
        // alert("issuing\n" + this.current_reply);
        if(this.pending_command)
            this.pending_command(this.current_reply);
        else {
            var code = this.current_reply[0].split(" ", 1)[0];
            if(code == "451" || code == "421") {
                this.disconnect();
                //SMTP timeout, just pass on the disconnect message
            } else {
                alert("unexpected reply: " + this.current_reply);
            }
        }
        this.current_reply = []
        this.pending_command = undefined;
        this.internalNextCommand();
    }
};


/**
 * @param {Array.<string>} emails
 */
function elimateDuplicateAddreses(emails, skip) {
    var mushed = {};
    for(var i = 0; i < emails.length; ++i) {
        mushed[emails[i]] = true;
    }
    if(skip) {
        for(var i = 0; i < skip.length; ++i) {
            delete mushed[skip[i]];
        }
    }
    var remaining = [];
    for(var i in mushed) {
        i = i.trim();
        if(i.length == 0)
            continue;
        remaining.push(i);
    }
    return remaining;
}

