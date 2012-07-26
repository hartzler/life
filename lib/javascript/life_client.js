function LifeClient() {
    this.logger = undefined;
    this.inbox = undefined;
    this.life = undefined;
    this.sender = undefined;
    this.options = undefined; // email, clear_cache, imap_server, password, logging, smtp_server
    this.idle = undefined;
    this.phases_left = undefined;
    this.connect_errors = undefined;
    this.db = undefined;
    this.next_inbox_uid = undefined;
    this.next_life_uid = undefined;
    this.life_folder_id = undefined;
    this.inbox_folder_id = undefined;
    this.offline_toggles = [];
    this.notify= // function(obj)
    this.objify = undefined; // function(str) -> obj
}

LifeClient.prototype.onConnectFailed = function(on_error) {
    this.disconnect();
    on_error("Check your account and server settings.  Also make sure you are connected.\n\n" + this.connect_errors.join("\n"));
}
LifeClient.prototype.onConnectPhaseSuccess = function(phase, on_success, on_error, on_offline_toggle) {
    this.phases_left--;
    if(this.phases_left > 0)
        return;
    if(this.connect_errors.length > 0) {
        this.onConnectFailed(on_error);
        return;
    }
    this.idle = this.inbox.hasCapability("IDLE");
    var life = this;
    life.life.openOrCreateFolder("Life", 
        function() {
            life.logger.debug("life client life all connected");
            try {
                life.openDatabase();
                life.startInboxProcessing();
                life.startObjectImport();
            } catch(err) {
                life.disconnect();
                on_error("Opening database failed: " + err)
                return;
            }
            life.offline_toggles.push(on_offline_toggle);
            on_success();
        }, function(e) {
            life.disconnect();
            on_error(e);
        }
    );
}
LifeClient.prototype.onConnectPhaseError = function(phase, on_error, error) {
    var err_msg = "" + error;
    if(err_msg.indexOf('OFFLINE') != -1) {
        err_msg = "Offline, cannot connect";
    }
    this.connect_errors.push(phase + " says " + err_msg + ".");
    this.phases_left--;
    if(this.phases_left > 0)
        return;
    this.onConnectFailed(on_error);
}
LifeClient.prototype.isOnline = function() {
    return this.inbox && this.inbox.socket && this.life && this.life.socket && this.inbox.fully_connected && this.life.fully_connected;
}

LifeClient.prototype.openDatabase = function() {
    var file = Components.classes["@mozilla.org/file/directory_service;1"]
                         .getService(Components.interfaces.nsIProperties)
                         .get("ProfD", Components.interfaces.nsIFile);
    var db_name = this.options['email'].replace(/[^\w\d\.]/g, function(c) { return "" + c.charCodeAt(0); });
    file.append(db_name + ".sqlite");

    this.logger.debug("Opening database: " + file.path)
    var storageService = Components.classes["@mozilla.org/storage/service;1"]
                            .getService(Components.interfaces.mozIStorageService);
    this.db = storageService.openDatabase(file); // Will also create the file if it does not exist
    
    var version = 1;
    var db_version = 0;
    //if the table doesn't exist then we should update
    try {
        var st_version = this.db.createStatement("SELECT version FROM versions");
        while(st_version.step()) {
            db_version = st_version.row.version;
        }
        st_version.finalize();
    } catch(e) {}

    if(this.options["clear_cache"] || db_version != version) {
        this.logger.debug("clearing sqlite tables!")
        this.db.beginTransaction();
        var st_table = this.db.createStatement("SELECT name FROM sqlite_master WHERE type='table'");
        var tables = [];
        while(st_table.step()) {
            tables.push(st_table.row.name);
        }
        for(var i = 0; i < tables.length; ++i) {
            try { this.db.executeSimpleSQL("DROP TABLE " + tables[i]); } catch(e) {}
        }
        this.db.commitTransaction();
        this.db.executeSimpleSQL("VACUUM");
    }
    this.db.beginTransaction();
    try {
        if(!this.db.tableExists("versions")) {
            var fields = [
                "version INTEGER UNIQUE"
            ];        
            this.db.createTable("versions", fields.join(", "));
            this.db.executeSimpleSQL("INSERT INTO versions (version) VALUES (" + version + ") ");
        }
        if(!this.db.tableExists("folders")) {
            var fields = [
                "folder_id INTEGER PRIMARY KEY",
                "name TEXT UNIQUE",                        //name of an imap folder (INBOX, Life, Sent)
                "next_uid INTEGER",                        //next id to consider when scanning
            ];
            this.db.createTable("folders", fields.join(", "));
            this.db.executeSimpleSQL("CREATE UNIQUE INDEX folders_by_folder_id ON folders (folder_id)");
            this.db.executeSimpleSQL("CREATE UNIQUE INDEX folders_by_name ON folders (name)");
        }
        this.db.executeSimpleSQL("INSERT OR IGNORE INTO folders (name, next_uid) VALUES ('INBOX', 1)");
        this.db.executeSimpleSQL("INSERT OR IGNORE INTO folders (name, next_uid) VALUES ('Life', 1)");
        var qfs = this.db.createStatement("SELECT folder_id FROM folders WHERE name = :folder");
        qfs.params.folder = "INBOX";
        while(qfs.step()) {
            this.inbox_folder_id = qfs.row.folder_id;
        }
        qfs.params.folder = "Life";
        while(qfs.executeStep()) {
            this.life_folder_id = qfs.row.folder_id;
        }
        qfs.finalize();
        if(!this.db.tableExists("messages")) {
            var fields = [
                "message_id INTEGER PRIMARY KEY",
                "folder_id INTEGER",
                "message_unique TEXT",
                "date INTEGER",
                "imap_uid INTEGER",
            ];
            this.db.createTable("messages", fields.join(", "));
            this.db.executeSimpleSQL("CREATE UNIQUE INDEX messages_by_message_id ON messages (folder_id, message_id)");
            this.db.executeSimpleSQL("CREATE UNIQUE INDEX messages_by_imap_uid ON messages (folder_id, imap_uid)");
            this.db.executeSimpleSQL("CREATE UNIQUE INDEX messages_by_unique ON messages (folder_id, message_unique)");
            this.db.executeSimpleSQL("CREATE INDEX messages_by_date ON messages (folder_id, date)");
        }
        this.db.commitTransaction();
    } catch(e) {
        this.db.rollbackTransaction();
        throw e;
    }
    this.st_folder_has_uid = this.db.createStatement("SELECT 1 FROM messages WHERE messages.folder_id = :folder AND messages.imap_uid = :uid");
    this.st_insert_message = this.db.createStatement("INSERT INTO messages (folder_id, message_unique, date, imap_uid) " +
        "VALUES (" + this.life_folder_id + ", :unique, :date, :uid);");
    this.st_set_next_uid = this.db.createStatement("UPDATE folders SET next_uid = :next WHERE name = :folder");
    this.st_get_next_uid = this.db.createStatement("SELECT next_uid FROM folders WHERE name = :folder");
}

LifeClient.prototype.startInboxProcessing = function() {
    this.st_get_next_uid.params.folder = "INBOX";
    while(this.st_get_next_uid.step()) {
        this.next_inbox_uid = this.st_get_next_uid.row.next_uid;
    }
    // alert("next inbox: " + this.next_inbox_uid);
    this.onNewInbox();
}
LifeClient.prototype.onNewInbox = function() {
    var life = this;
    life.inbox.listMessages("INBOX", undefined, this.next_inbox_uid, true, 
        function(ids, next_uid) {
            if(ids.length == 0) {
                life.next_inbox_uid = next_uid;
                if(!life.idle) {
                    window.setTimeout(bind(life.onNewInbox, life), 30000);
                    return;                    
                } else {
                    life.inbox.waitMessages("INBOX", life.next_inbox_uid, 
                        bind(life.onNewInbox, life),
                        function(error) {
                            life.logger.error("failed to wait for inbox messages, reconnect needed...", error);
                        }
                    )
                    return;
                }
            }
            life.next_inbox_uid = next_uid;
            life.inbox.copyMessage("Life", "INBOX", ids, 
                function() {
                    life.inbox.deleteMessage("INBOX", ids, 
                        function() {
                            life.st_set_next_uid.params.folder = "INBOX";
                            life.st_set_next_uid.params.next = next_uid;
                            while(life.st_set_next_uid.step()) {};
                            //if there is no idle, we won't wake up so do it this way
                            if(!life.idle) 
                                life.onNewLife();
                        }, function(error) {
                            //hmm...this is BAD
                            life.logger.error("failed to delete messages, mailbox will be getting wastefully full", error);
                        }
                    );
                    //TODO: if no idle then do the alternative
                    if(!life.idle) {
                        window.setTimeout(bind(life.onNewInbox, life), 30000);
                    } else {
                        life.inbox.waitMessages("INBOX", life.next_inbox_uid, 
                            bind(life.onNewInbox, life),
                            function(error) {
                                life.logger.error("failed to wait for message messages, reconnect needed...", error);
                            }
                        );
                    }
                },
                function(e) {
                    life.logger.error("failed to copy messages, items will be temporarily lost", error);
                }
            );
        }, function(e) {
            alert("Listing inbox failed!\n" + e);
        }
    );
}
LifeClient.prototype.startObjectImport = function() {
    this.st_get_next_uid.params.folder = "Life";
    while(this.st_get_next_uid.step()) {
        this.next_life_uid = this.st_get_next_uid.row.next_uid;
    }
    // alert("next life: " + this.next_life_uid);
    this.onNewLife();
}
LifeClient.prototype.onNewLife = function() {
    var life = this;
    if(life.life_timeout) {
        window.clearTimeout(life.life_timeout);
        life.life_timeout = undefined;
    }
    life.life.listMessages("Life", undefined, this.next_life_uid, true, 
        function(ids, next_uid) {
            if(ids.length == 0) {
                life.next_life_uid = next_uid;
                if(!life.idle) {
                    life.life_timeout = window.setTimeout(bind(life.onNewLife, life), 30000);
                    return;
                } else {
                    life.life.waitMessages("Life", life.next_life_uid, 
                        bind(life.onNewLife, life),
                        function(error) {
                            life.logger.error("failed to wait for life messages, reconnect needed...", error);
                        }
                    )
                    return;
                }
            }
            life.next_life_uid = next_uid;
            //TODO: if there are a bunch of bad messages at the head of the inbox, then they get redownloaded and scanned each
            //start until a valid one comes in
            life.life.getLifeMessage("Life", ids,
                function(hits) {
                    if(hits.length == 0) {
                        life.logger.debug("no new messages parsed successfully...");
                        return;
                    }
                    
                    //need to sort by uid to ensure that the "first message wins" dedupe strategy works
                    hits.sort(function(a, b) { return a.uid < b.uid; });
                    life.db.beginTransaction();
                    try {
                        for(var i = 0; i < hits.length; ++i) {
                            var msg = hits[i];
                            life.logger.debug("processing message: " + JSON.stringify(msg));

                            // should throw an error if something wrong so we try again...
                            life.notify(msg.objs[0]);

                            life.st_insert_message.params.unique = msg.id;
                            life.st_insert_message.params.date = msg.date.getTime();
                            life.st_insert_message.params.uid = msg.uid;
                            try {
                                while(life.st_insert_message.step()) {};
                            } catch(e) {
                                if(life.db.lastError == 19) {
                                    life.st_insert_message.reset();
                                    life.st_folder_has_uid.params.folder = life.life_folder_id;
                                    life.st_folder_has_uid.params.uid = msg.uid;
                                    var duplicate_by_uid = false;
                                    while(life.st_folder_has_uid.step()) {
                                        duplicate_by_uid = true;
                                    }
                                    if(!duplicate_by_uid) {
                                        life.life.deleteMessage("Life", msg.uid, function() {}, function() {});
                                    }
                                    continue;
                                } else {
                                    throw e;
                                }
                            }
                        }
                        life.st_set_next_uid.params.folder = "Life";
                        life.st_set_next_uid.params.next = next_uid;
                        while(life.st_set_next_uid.step()) {};
                        life.db.commitTransaction();
                    } catch(e) {
                        life.logger.error("failed inserting objects: " + life.db.lastErrorString,e);
                        life.db.rollbackTransaction();
                    }

                    //TODO: if no idle then do the alternative
                    if(!life.idle) {
                        life.life_timeout = window.setTimeout(bind(life.onNewLife, life), 30000);
                    } else {
                        life.life.waitMessages("Life", life.next_life_uid, 
                            bind(life.onNewLife, life),
                            function(error) {
                                life.logger.error("failed to wait for life messages, reconnect needed...", error);
                            }
                        );
                    }

                }, function(msg) {
                    on_error("Fetching messages failed", msg);
                }
            );
        }, function(e) {
            alert("Listing life failed!\n" + e);
        }
    );
}
LifeClient.prototype.handlePartialReconnect = function() {
    if(this.isOnline()) {
        for(var i in this.offline_toggles) {
            this.offline_toggles[i]();
        }
    }
}
LifeClient.prototype.onInboxDisconnect = function() {
    this.logger.debug("life client inbox disconnect");
    this.inbox = undefined;
    for(var i in this.offline_toggles) {
        this.offline_toggles[i]();
    }
    if(!this.reconnect_inbox_timeout)
        this.reconnect_inbox_timeout = window.setTimeout(bind(this.tryInboxAgain, this), 30000);
}
LifeClient.prototype.tryInboxAgain = function() {
    if(this.inbox) {
        alert("inbox already connected");
        return;
    }
    var life = this;
    life.reconnect_inbox_timeout = undefined;
    this.inbox = new SslImapClient();
    this.inbox.connect(this.options["imap_server"], this.options['email'], this.options['password'], 
        function() {
            life.logger.debug("life client inbox reconnected");
            life.handlePartialReconnect();
            life.startInboxProcessing();
        }, function() {
            life.inbox = undefined;
            alert("Email password rejected, Life will be disabled!");
        }, function(e) {
            life.inbox = undefined;
            life.reconnect_inbox_timeout = window.setTimeout(bind(life.tryInboxAgain, life), 30000);
        },
        bind(this.onInboxDisconnect, this), 
        this.options['logging']
    );    
}
LifeClient.prototype.onLifeDisconnect = function() {
    this.logger.debug("life client life disconnect");
    this.life = undefined;
    for(var i in this.offline_toggles) {
        this.offline_toggles[i]();
    }
    if(!this.reconnect_life_timeout)
        this.reconnect_life_timeout = window.setTimeout(bind(this.tryLifeAgain, this), 30000);
}
LifeClient.prototype.tryLifeAgain = function() {
    if(this.life) {
        alert("life already connected");
        return;
    }
    var life = this;
    life.reconnect_life_timeout = undefined;
    this.life = new SslImapClient();
    this.life.connect(this.options["imap_server"], this.options['email'], this.options['password'], 
        function() {
            life.logger.debug("life client life reconnected");
            life.handlePartialReconnect();
            life.startObjectImport();
        }, function() {
            life.life = undefined;
            alert("Email password rejected, Life will be disabled!");
        }, function(e) {
            life.life = undefined;
            life.reconnect_life_timeout = window.setTimeout(bind(life.tryLifeAgain, life), 30000);
        },
        bind(this.onLifeDisconnect, this), 
        this.options['logging']
    );    
}
LifeClient.prototype.onSenderDisconnect = function() {
    this.logger.debug("life client sender disconnect");
    this.sender = undefined;
}

LifeClient.prototype.connect = function(options, on_success, on_error, on_offline_toggle) {
    if(this.connected)
        on_error("You are already connected");
    if(options['email'] == undefined || options['email'].length == 0)
        return on_error("Missing email!");
    if(options['email'].indexOf('@') == -1)
        return on_error("Email address invalid.");
    if(options['password'] == undefined || options['password'].length == 0)
        return on_error("Missing password!");
    if(options['imap_server'] == undefined || options['imap_server'].length == 0)
        return on_error("Missing IMAP server!");
    if(options['smtp_server'] == undefined || options['smtp_server'].length == 0)
        return on_error("Missing SMTP server!");

    if(options['email'].indexOf('@') == -1)
        return on_error("Email address invalid.");

    var validated = options['validated'];
    this.options = deep_copy(options);

    this.connect_errors = [];
    if(!validated) {
        this.phases_left = 2;
        this.inbox = new SslImapClient();
        this.inbox.connect(options["imap_server"], options['email'], options['password'], 
            bind(this.onConnectPhaseSuccess, this, "IMAP inbox", on_success, on_error, on_offline_toggle), 
            bind(this.onConnectPhaseError, this, "IMAP inbox", on_error, "bad username or password"), 
            bind(this.onConnectPhaseError, this, "IMAP inbox", on_error), 
            bind(this.onInboxDisconnect, this), 
            options['logging']
        );
        this.life = new SslImapClient();
        this.life.connect(options["imap_server"], options['email'], options['password'], 
            bind(this.onConnectPhaseSuccess, this, "IMAP aux", on_success, on_error, on_offline_toggle), 
            bind(this.onConnectPhaseError, this, "IMAP aux", on_error, "bad username or password"), 
            bind(this.onConnectPhaseError, this, "IMAP aux", on_error), 
            bind(this.onLifeDisconnect, this), 
            options['logging']
        );
    } 
    this.phases_left++;
    this.sender = new SslSmtpClient();
    this.sender.connect(options["smtp_server"], options['email'], options['password'], 
        bind(this.onConnectPhaseSuccess, this, "SMTP sender", on_success, on_error, on_offline_toggle), 
        bind(this.onConnectPhaseError, this, "SMTP sender", on_error, "bad username or password"), 
        bind(this.onConnectPhaseError, this, "SMTP sender", on_error), 
        bind(this.onSenderDisconnect, this), 
        options['logging']
    );
}
LifeClient.prototype.disconnect = function() {
    if(this.inbox) {
        this.inbox.disconnect();
        this.inbox = undefined;
    }
    if(this.life) {
        this.life.disconnect();
        this.life = undefined;
    }
    if(this.sender) {
        this.sender.disconnect()
        this.sender = undefined;
    }
    if(this.db) {
        try {
            this.db.close();
        } catch (e) {}
        this.db = undefined;
    }
}

// local then remote store
LifeClient.prototype.send = function(to, subject, related, html, txt, base64, tag, on_success, on_error) {
    this.logger.debug("LifeClient.send: tag=" + tag + " to=" + to.toSource() + " subject=" + subject + " base64=" + base64);

    if(!this.sender) {
       on_error("sender not connected...");
       return;
    }

    this.sender.sendMessage(tag, to, subject, related, html, txt, base64, on_success, on_error);
}
