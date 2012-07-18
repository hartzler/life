function LifeObject() {
    this.tag = undefined;
    this.date = undefined;
    this.from = undefined;
    this.to = undefined;
    this.obj = undefined;
}

function LifeClient() {
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
    this.waiters = {};
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
            Cu.reportError("life client life all connected");
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
        if(!this.db.tableExists("objects")) {
            var fields = [
                "object_id INTEGER PRIMARY KEY",
                "message_id INTEGER",               //tells what message the object came from, for finding attachments, etc
            ];        
            this.db.createTable("objects", fields.join(", "));
            this.db.executeSimpleSQL("CREATE UNIQUE INDEX objects_by_object_id ON objects (object_id)");
            this.db.executeSimpleSQL("CREATE INDEX objects_by_message_id ON objects (message_id)");
        }
        if(!this.db.tableExists("people")) {
            var fields = [
                "person_id INTEGER PRIMARY KEY",
                "name TEXT",                        //the name of the person
                "email TEXT UNIQUE",                 //the email of the person
            ];
            this.db.createTable("people", fields.join(", "));
            this.db.executeSimpleSQL("CREATE UNIQUE INDEX people_by_person_id ON people (person_id)");
        }
        if(!this.db.tableExists("groups")) {
            var fields = [
                "group_id INTEGER PRIMARY KEY",
                "name TEXT",                        //the name for a group if this is a user defined group
                "flattened TEXT",                   //flattened array of people ids e.g. 1:2:5:10 in sorted order
            ];
            this.db.createTable("groups", fields.join(", "));
            this.db.executeSimpleSQL("CREATE UNIQUE INDEX groups_by_group_id ON groups (group_id)");
            this.db.executeSimpleSQL("CREATE INDEX groups_by_flattened ON groups (flattened)");
        }
        if(!this.db.tableExists("members")) {
            var fields = [
                "group_id INTEGER",                 //a group that contains
                "person_id INTEGER",                //this member
            ];
            this.db.createTable("members", fields.join(", "));
            this.db.executeSimpleSQL("CREATE INDEX members_by_group_id ON members (group_id)");
        }
        this.db.executeSimpleSQL("CREATE TRIGGER IF NOT EXISTS group_add_member AFTER INSERT ON members BEGIN UPDATE groups SET flattened = (SELECT GROUP_CONCAT(pid, ':') FROM(SELECT members.person_id AS pid FROM members WHERE members.group_id = new.group_id ORDER BY members.person_id)) WHERE new.group_id = groups.group_id; END;");
        this.db.executeSimpleSQL("CREATE TRIGGER IF NOT EXISTS group_delete_member AFTER DELETE ON members BEGIN UPDATE groups SET flattened = (SELECT GROUP_CONCAT(pid, ':') FROM(SELECT members.person_id AS pid FROM members WHERE members.group_id = old.group_id ORDER BY members.person_id)) WHERE old.group_id = groups.group_id; END;");
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
                "from_id INTEGER",
                "to_id INTEGER",
                "type TEXT",                        //life tag
            ];
            this.db.createTable("messages", fields.join(", "));
            this.db.executeSimpleSQL("CREATE UNIQUE INDEX messages_by_message_id ON messages (folder_id, message_id)");
            this.db.executeSimpleSQL("CREATE UNIQUE INDEX messages_by_type_and_imap_uid ON messages (folder_id, type, imap_uid)");
            this.db.executeSimpleSQL("CREATE UNIQUE INDEX messages_by_unique ON messages (folder_id, message_unique)");
            this.db.executeSimpleSQL("CREATE INDEX messages_by_type_and_date ON messages (folder_id, type, date)");
        }
        if(!this.db.tableExists("properties")) {
            var fields = [
                "object_id INTEGER",
                "property TEXT",
                "value",
            ];
            this.db.createTable("properties", fields.join(", "));
            this.db.executeSimpleSQL("CREATE INDEX properties_by_object_id ON properties (object_id)");
            this.db.executeSimpleSQL("CREATE INDEX properties_by_object_id_and_property ON properties (object_id, property)");
            this.db.executeSimpleSQL("CREATE INDEX properties_by_object_id_and_property_and_value ON properties (object_id, property, value)");
        }
        if(!this.db.tableExists("attachments")) {
            var fields = [
                "message_id INTEGER",
                "part TEXT",
                "content_type TEXT",
                "cache_path TEXT",
            ];
            this.db.createTable("attachments", fields.join(", "));
            this.db.executeSimpleSQL("CREATE INDEX attachments_by_message_id ON attachments (message_id)");
        }
        this.db.commitTransaction();
    } catch(e) {
        this.db.rollbackTransaction();
        throw e;
    }
    this.st_folder_has_uid = this.db.createStatement("SELECT 1 FROM messages WHERE messages.folder_id = :folder AND messages.imap_uid = :uid");
    this.st_get_person_by_email = this.db.createStatement("SELECT person_id FROM people WHERE email = :email");
    this.st_insert_person = this.db.createStatement("INSERT INTO people (email) VALUES (:email);");
    this.st_get_group_by_flattened = this.db.createStatement("SELECT group_id FROM groups WHERE flattened = :flattened");
    this.st_create_generic_group = this.db.createStatement("INSERT INTO groups (flattened) VALUES ('');");
    this.st_insert_group_member = this.db.createStatement("INSERT INTO members (group_id, person_id) VALUES (:group, :person)");
    this.st_insert_message = this.db.createStatement("INSERT INTO messages (folder_id, message_unique, date, imap_uid, from_id, to_id, type) " +
        "VALUES (" + this.life_folder_id + ", :unique, :date, :uid, :from, :to, :type);");
    this.st_insert_object = this.db.createStatement("INSERT INTO objects (message_id) VALUES (:message);");
    this.st_insert_property = this.db.createStatement("INSERT INTO properties (object_id, property, value) VALUES (:object, :property, :value)");
    this.st_get_object = this.db.createStatement("SELECT properties.property, properties.value FROM objects LEFT OUTER JOIN properties ON properties.object_id = objects.object_id WHERE objects.object_id = :object");
    this.st_get_object_meta = this.db.createStatement("SELECT messages.message_id, messages.date, messages.type, people.email FROM objects JOIN messages ON messages.message_id = objects.message_id, people ON messages.from_id = people.person_id WHERE objects.object_id = :object");
    this.st_get_object_to = this.db.createStatement("SELECT people.email FROM objects JOIN messages ON messages.message_id = objects.message_id JOIN members ON messages.to_id = members.group_id JOIN people ON people.person_id = members.person_id WHERE objects.object_id = :object");
    //TODO: needs to pick life folder...
    this.st_list_objects = this.db.createStatement("SELECT objects.object_id FROM messages JOIN objects ON messages.message_id = objects.message_id WHERE messages.type = :type AND messages.folder_id = :folder ORDER BY messages.date");
    this.st_list_objects_starting_at = this.db.createStatement("SELECT objects.object_id FROM messages JOIN objects ON messages.message_id = objects.message_id WHERE messages.type = :type AND objects.object_id >= :start  AND messages.folder_id = :folder ORDER BY messages.date");
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
                            Cu.reportError("failed to wait for inbox messages, reconnect needed..." + error);
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
                            Cu.reportError("failed to delete messages, mailbox will be getting wastefully full" + error);
                        }
                    );
                    //TODO: if no idle then do the alternative
                    if(!life.idle) {
                        window.setTimeout(bind(life.onNewInbox, life), 30000);
                    } else {
                        life.inbox.waitMessages("INBOX", life.next_inbox_uid, 
                            bind(life.onNewInbox, life),
                            function(error) {
                                Cu.reportError("failed to wait for message messages, reconnect needed..." + error);
                            }
                        );
                    }
                },
                function(e) {
                    Cu.reportError("failed to copy messages, items will be temporarily lost" + error);
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
LifeClient.prototype.getOrInsertPerson = function(email) {
    var person_id = undefined;
    this.st_get_person_by_email.params.email = email;
    while(this.st_get_person_by_email.step()) {
        person_id = this.st_get_person_by_email.row.person_id;
    }
    if(person_id != undefined)
        return person_id;
    this.st_insert_person.params.email = email;
    while(this.st_insert_person.step()) {};
    return this.db.lastInsertRowID;
}
LifeClient.prototype.getOrInsertGroup = function(emails) {
    var pid_map = {};
    for(var i = 0; i < emails.length; ++i) {
        pid_map[this.getOrInsertPerson(emails[i])] = emails[i];
    }
    var pids = [];
    for(var i in pid_map) {
        pids.push(i);
    }
    pids.sort();
    var group_id = undefined;
    this.st_get_group_by_flattened.params.flattened = pids.join(":");
    while(this.st_get_group_by_flattened.step()) {
        group_id = this.st_get_group_by_flattened.row.group_id;
    }
    if(group_id != undefined)
        return group_id;
    while(this.st_create_generic_group.step()) {};
    group_id = this.db.lastInsertRowID;
    for(var i = 0; i < pids.length; ++i) {
        this.st_insert_group_member.params.group = group_id;
        this.st_insert_group_member.params.person = pids[i];
        while(this.st_insert_group_member.step()) {};
    }
    return group_id;
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
                            Cu.reportError("failed to wait for life messages, reconnect needed..." + error);
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
                        Cu.reportError("no new messages parsed successfully...");
                        return;
                    }
                    
                    var tags = {};
                    //need to sort by uid to ensure that the "first message wins" dedupe strategy works
                    hits.sort(function(a, b) { return a.uid < b.uid; });
                    life.db.beginTransaction();
                    try {
                        for(var i = 0; i < hits.length; ++i) {
                            var msg = hits[i];
                            // Cu.reportError(JSON.stringify(msg));
                            life.st_insert_message.params.unique = msg.id;
                            life.st_insert_message.params.date = msg.date.getTime();
                            life.st_insert_message.params.uid = msg.uid;
                            life.st_insert_message.params.from = life.getOrInsertPerson(msg.from);
                            life.st_insert_message.params.to = life.getOrInsertGroup(msg.to);
                            life.st_insert_message.params.type = msg.tag;
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
                                        //if it is duplicated by UID then we still want to wake up because 
                                        //some other life client inserted it into the db (another ffx window)
                                        tags[msg.tag] = true;
                                    }
                                    if(!duplicate_by_uid) {
                                        life.life.deleteMessage("Life", msg.uid, function() {}, function() {});
                                    }
                                    continue;
                                } else {
                                    throw e;
                                }
                            }
                            tags[msg.tag] = true;
                            var message_id = life.db.lastInsertRowID;
                            life.st_insert_object.params.message = message_id;
                            for(var j = 0; j < msg.objs.length; ++j) {
                                while(life.st_insert_object.step()) {};
                                var object_id = life.db.lastInsertRowID;
                                var obj = msg.objs[j];
                                for(var prop in obj) {
                                    var v = obj[prop];
                                    if(v instanceof Array && v.unordered)  {
                                        for(var k = 0; k < v.length; ++k) {
                                            life.st_insert_property.params.object = object_id;
                                            life.st_insert_property.params.property = prop;
                                            life.st_insert_property.params.value = JSON.stringify(v[k]);
                                            while(life.st_insert_property.step()) {};
                                        }
                                    } else {
                                        life.st_insert_property.params.object = object_id;
                                        life.st_insert_property.params.property = prop;
                                        life.st_insert_property.params.value = JSON.stringify(v);
                                        while(life.st_insert_property.step()) {};
                                    }
                                }
                            }
                            
                        }
                        life.db.commitTransaction();
                    } catch(e) {
                        alert("failed inserting objects:\n" + e + "\n" + life.db.lastErrorString);
                        life.db.rollbackTransaction();
                    }
                    var cbs = [];
                    for(var t in tags) {
                        if(t in life.waiters) {
                            cbs.push.apply(cbs, life.waiters[t]);
                            delete life.waiters[t];
                        }
                    }
                    life.st_set_next_uid.params.folder = "Life";
                    life.st_set_next_uid.params.next = next_uid;
                    while(life.st_set_next_uid.step()) {};

                    for(var i = 0; i < cbs.length; ++i) {
                        cbs[i]();
                    }
                    //TODO: if no idle then do the alternative
                    if(!life.idle) {
                        life.life_timeout = window.setTimeout(bind(life.onNewLife, life), 30000);
                    } else {
                        life.life.waitMessages("Life", life.next_life_uid, 
                            bind(life.onNewLife, life),
                            function(error) {
                                Cu.reportError("failed to wait for life messages, reconnect needed..." + error);
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
    Cu.reportError("life client inbox disconnect");
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
            Cu.reportError("life client inbox reconnected");
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
    Cu.reportError("life client life disconnect");
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
            Cu.reportError("life client life reconnected");
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
    Cu.reportError("life client sender disconnect");
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
LifeClient.prototype.getData = function(id) {
    this.st_get_object.params.object = id;
    var obj = undefined;
    while(this.st_get_object.step()) {
        if(!obj) {
            obj = {};
        }
        var val;
        try {
            val = JSON.parse(this.st_get_object.row.value);
        } catch(e) {
            Cu.reportError("failed to parse property data: \n" + this.st_get_object.row.value);
            this.st_get_object.reset();
            return undefined;
        }
        if(this.st_get_object.row.property in obj) {
            if(obj[this.st_get_object.row.property].unordered) {
                obj[this.st_get_object.row.property].push(val);
            } else {
                var s = [];
                s.push(obj[this.st_get_object.row.property]);
                s.push(val);
                s.unordered = true;
                obj[this.st_get_object.row.property] = s;
            }
        } else {
            obj[this.st_get_object.row.property] = val;
        }
    }
    return obj;
}
LifeClient.prototype.get = function(id) {
    var obj = new LifeObject();
    obj.obj = this.getData(id);
    if(obj.obj == undefined)
        return undefined;
    this.st_get_object_meta.params.object = id;
    while(this.st_get_object_meta.step()) {
        obj.tag = this.st_get_object_meta.row.type;
        obj.date = new Date(this.st_get_object_meta.row.date);
        obj.from = this.st_get_object_meta.row.email;
    }
    this.st_get_object_to.params.object = id;
    obj.to = [];
    while(this.st_get_object_to.step()) {
        obj.to.push(this.st_get_object_to.row.email);
    }
    return obj;
}
LifeClient.prototype.list = function(start_id, tag) {
    var st;
    if(start_id != undefined) {
        st = this.st_list_objects_starting_at;
        st.params.start = start_id;
    } else {
        st = this.st_list_objects;
    }
    st.params.folder = this.life_folder_id;
    st.params.type = tag;
    var objects = [];
    while(st.step()) {
        objects.push(st.row.object_id);
    }
    return objects;
}
LifeClient.prototype.wait = function(start_id, tag, on_success) {
    //we do the list inside because if there was any async handling in between the callers
    //last call to list, we want to catch it... not really necessary right now though    
    if(this.list(start_id, tag).length > 0) {
        on_success();
        return;
    }
    if(!(tag in this.waiters)) this.waiters[tag] = [];
    this.waiters[tag].push(on_success);
}
LifeClient.prototype.send = function(tag, to, subject, related, html, txt, obj, on_success, on_error) {
    if(this.sender) {
        this.sender.sendMessage(tag, to, subject, related, html, txt, obj, on_success, on_error);
        return;
    }

    var life = this;
    life.sender = new SslSmtpClient();
    life.sender.connect(life.options["smtp_server"], life.options['email'], life.options['password'], 
        function() {
            Cu.reportError("sender connected");
            life.sender.sendMessage(tag, to, subject, related, html, txt, obj, on_success, on_error);
        }, function() {
            life.sender = undefined;
            on_error("SMTP says bad username/password");
        }, function(err) {
            life.sender = undefined;
            var err_msg = "" + err;
            if(err_msg.indexOf('OFFLINE') != -1) {
                on_error("Offline, cannot connect to " + life.options["smtp_server"], err_msg);
                return;
            }
            on_error("Failed to connect to " + life.options["smtp_server"], err_msg);
        }, 
        bind(this.onSenderDisconnect, this), 
        life.options['logging']
    );
}
