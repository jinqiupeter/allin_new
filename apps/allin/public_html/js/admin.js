
var State = {
    IDLE: 0,
    SIGNIN: 1,
    CONNECTING: 2,
    CONNECTED: 3
};

var f2num = function(n, l) {
    if (typeof l === "undefined") l = 2;
    while (n.length < l) {
        n = "0" + n;
    }
    return n;
}

var HTTP_ENTRY      = "allin_api";
var WEBSOCKET_ENTRY = "allin_socket";

var AdminApp = function (apphtml) {
    var self = this;

    self._state    = State.IDLE;
    self._socket   = null;

    self._apphtml  = apphtml;
}

AdminApp.prototype.init = function() {
    var self = this;

    var apphtml = self._apphtml;

    // sign in
    self._usernameInput     = apphtml.find("#username");
    self._passwordInput     = apphtml.find("#password");
    self._serverAddrInput   = apphtml.find("#serverAddr");
    self._signInButton      = apphtml.find("#signInButton");

    self._serverAddrInput.val(document.location.host);

    self._signInButton.click(function() {
        if (self._state === State.IDLE) {
            self.signIn();
        } else {
            self.signOut();
        }
    });


    // chat
    self._selectUserInput   = apphtml.find("#selectUser");
    self._messageInput      = apphtml.find("#message");
    self._sendMessageButton = apphtml.find("#sendMessageButton");
    self._sendMessageToAllButton = apphtml.find("#sendMessageToAllButton");

    self._sendMessageButton.click(function() {
        var recipient = self._selectUserInput.val();
        var message = self._messageInput.val();
        self.sendMessage(recipient, message);
    });

    self._sendMessageToAllButton.click(function() {
        var message = self._messageInput.val();
        self.sendMessageToAll(message);
    });

    // log

    self._alertDialogHtml   = apphtml.find("#alertDialog");
    self._logHtml           = apphtml.find("#log");

    apphtml.find("#clearLogsButton").click(function() {
        self._clearLogs();
    });

    apphtml.find("#insertMarkButton").click(function() {
        self._appendLogMark();
    });

    // init
    self._updateUI();
}

AdminApp.prototype.signIn = function() {
    var self = this;

    var username = self._usernameInput.val();
    if (username === "") {
        self._showError("PLEASE ENTER username");
        return;
    }

    var password = self._passwordInput.val();
    if (password === "") {
        self._showError("PLEASE ENTER password");
        return;
    }

    var serverAddr = self._serverAddrInput.val();
    if (serverAddr === "") {
        self._showError("PLEASE ENTER server addr");
        return;
    }

    self._httpServerAddr = "http://" + serverAddr + "/" + HTTP_ENTRY;
    self._websocketServerAddr = "ws://" + serverAddr + "/" + WEBSOCKET_ENTRY;

    self._state = State.SIGNIN;

    self._appendLogMark();
    self._appendLog("SIGN IN " + serverAddr);

    var data = {"phone": username, "password": password};
    //var data = JSON.stringify({phone: username, password: password})
    var values = {"data": data};
    var json = JSON.stringify(values);
    self._sendHttpRequest("auth.signin", json, function(res) {
        if (!self._validateResult(res, ["sid"])) {
            self._state = State.IDLE;
            self._showError("Get invalid result");
            self._appendLog(res.toString());
        } else {
            self._state = State.CONNECTING;
            self._sid = res["sid"];
            self._appendLog("GET SESSION ID: " + self._sid);

            var count = parseInt(res["count"]);
            self._appendLog("count = " + count.toString());

            self._connectWebSocket(self._sid);
        }

        self._updateUI();
    }, function() {
        self._state = State.IDLE;
        self._updateUI();
    });

    self._updateUI();
}

AdminApp.prototype.signOut = function() {
    var self = this;

    self._appendLogMark();
    self._appendLog("SIGN OUT");

    self._sendHttpRequest("auth.signout", {"sid": self._sid}, function(res) {
        if (self._socket) {
            // will call cleanup() and updateUI()
            self._socket.close();
        } else {
            self._cleanup();
            self._updateUI();
        }
    });
}


AdminApp.prototype.sendMessage = function(recipient, message) {
    var self = this;

    if (recipient === "" || recipient === null) {
        self._showError("Please choose user from online users list.");
        return;
    }

    if (message === "") {
        self._showError("Please enter message.");
    }

    var data = {
        action: "chat.sendmessage",
        recipient: recipient,
        message: message
    };
    self._sendWebSocketMessage(data);
}

AdminApp.prototype.sendMessageToAll = function(message) {
    var self = this;

    if (message === "") {
        self._showError("Please enter message.");
    }

    var data = {
        action: "admin.sendsystembroadcast",
        data: {content: message}
    };
    self._sendWebSocketMessage(data);
}

AdminApp.prototype._updateUI = function() {
    var self = this;

    var state = self._state;

    // sign in
    self._serverAddrInput.prop("disabled", state != State.IDLE);
    self._usernameInput.prop("disabled", state != State.IDLE);
    self._passwordInput.prop("disabled", state != State.IDLE);


    if (state === State.IDLE) {
        self._signInButton.text("Sign In").prop("disabled", false);
    } else if (state === State.SIGNIN || state === State.CONNECTING) {
        self._signInButton.text("Connecting").prop("disabled", true);
    } else if (state === State.CONNECTED) {
        self._signInButton.text("Sign Out").prop("disabled", false);
    } else {
        self._signInButton.text("-").prop("disabled", true);
    }


    // chat
    if (state != State.CONNECTING && state != State.CONNECTED) {
        self._selectUserInput.empty();
    }

    self._selectUserInput.prop("disabled", state != State.CONNECTED);
    self._messageInput.prop("disabled", state != State.CONNECTED);
    self._sendMessageButton.prop("disabled", state != State.CONNECTED);
    self._sendMessageToAllButton.prop("disabled", state != State.CONNECTED);
}

AdminApp.prototype._cleanup = function() {
    self._state               = State.IDLE;
    self._socket              = null;
    self._sid                 = null;
    self._httpServerAddr      = null;
    self._websocketServerAddr = null;
}

AdminApp.prototype._validateResult = function(res, fields) {
    var err = res["err"];
    if (typeof err !== "undefined") {
        return false;
    }

    for (var i = 0; i < fields.length; i++) {
        var field = fields[i];
        var v = res[field];
        if (typeof v === "undefined") {
            return false;
        }
    }
    return true;
}

AdminApp.prototype._sendHttpRequest = function(action, values, callback, fail) {
    var self = this;

    var url = self._httpServerAddr + "?action=" + action;
    self._appendLog("HTTP: " + url);
    self._appendLog("Content: " + values);

    $.ajax({
        url:url,
        type:"POST",
        data:values,
        contentType:"application/json",
        dataType:"json",
        success: function(res){
            if (res.err) {
                var err = "ERR: " + res.err;
                self._showError(err);
                self._appendLog(err);
            }
            if (callback) {
                callback(res);
            } else {
                if (res.ok) {
                    self._appendLog("OK");
                } else {
                    self._appendLog("ERR, " + res.err);
                }
            }
        },
        fail: function() {
            self._appendLog("HTTP: " + url + " FAILED");
            if (fail) {
                fail();
            }
        }
    });

    /*
    $.post(url, values, function(res) {
        if (res.err) {
            var err = "ERR: " + res.err;
            self._showError(err);
            self._appendLog(err);
        }
        if (callback) {
            callback(res);
        } else {
            if (res.ok) {
                self._appendLog("OK");
            } else {
                self._appendLog("ERR, " + res.err);
            }
        }
    }, "json")
    .fail(function() {
        self._appendLog("HTTP: " + url + " FAILED");
        if (fail) {
            fail();
        }
    });
    */
}

AdminApp.prototype._sendWebSocketMessage = function(data) {
    var self = this;

    var str = JSON.stringify(data);
    self._socket.send(str);
    self._appendLog("WEBSOCKET SEND: " + str);
}

AdminApp.prototype._connectWebSocket = function(sid) {
    var self = this;

    var protocol = "allin-auth-" + sid;
    self._appendLog("CONNECT WEBSOCKET with PROTOCOL: " + protocol);

    var socket = new WebSocket(self._websocketServerAddr, protocol);
    socket.onopen = function() {
        self._appendLog("WEBSOCKET CONNECTED");
        self._state = State.CONNECTED;
        self._updateUI();
    }

    socket.onerror = function(error) {
        if (!(error instanceof Event)) {
            self._appendLog("ERR: " + error.toString());
        }
    }

    socket.onmessage = function(event) {
        self._appendLog("WEBSOCKET RECV: " + event.data.toString());

        var msg = JSON.parse(event.data);
        if (typeof msg == "object" && msg.name) {
            var handler = self._messageHandlers[msg.name];
            if (handler) {
                handler(self, msg);
            }
        } else {
            //self._appendLog("INVALID MSG: " + event.data.toString());
        }
    }

    socket.onclose = function() {
        self._state = State.IDLE;
        self._appendLog("WEBSOCKET DISCONNECTED");
        self._cleanup();
        self._updateUI();
    }

    self._socket = socket;
}

AdminApp.prototype._messageHandlers = {
    LIST_ALL_USERS: function(self, data) {
        var users = data["users"];
        if (!users) {
            return;
        }

        self._selectUserInput.empty();
        for (var i = 0; i < users.length; ++i) {
            var username = users[i];
            var username_html = $("<div/>").text(users[i]).html();
            self._selectUserInput.append($("<option></option>")
                .val(username)
                .text(username_html));
        }
        self._selectUserInput.prop("selectedIndex", 0);
    },

    ADD_USER: function(self, data) {
        var username = data.username;
        self._selectUserInput.append($("<option></option>")
            .val(username)
            .text(username));
    },

    REMOVE_USER: function(self, data) {
        var username = data.username;
        self._selectUserInput.find("> option").each(function() {
            if ($(this).val() === username) {
                $(this).remove();
                return;
            }
        });
    },

    MESSAGE: function(self, data) {
        var username = data.sender;
        var message = data.body;
        UIkit.notify({
            message: "<strong>" + username + "</strong> say:<br />" + message,
            status: 'info',
            timeout: 5000,
            pos: 'bottom-right'
        });
    }
}

AdminApp.prototype._showError = function(message) {
    var self = this;
    self._alertDialogHtml.find("#alertContents").text(message);
    var modal = UIkit.modal(self._alertDialogHtml);
    modal.show();
}

AdminApp.prototype._appendLogMark = function() {
    var self = this;

    self._logHtml.prepend("<strong>--------<strong>\n");
    self._logHtml.scrollTop(self._logHtml.prop("scrollHeight"));
}

AdminApp.prototype._appendLog = function(message) {
    var self = this;

    var now = new Date();
    var time = f2num(now.getHours().toString())
                 + ":" + f2num(now.getMinutes().toString())
                 + ":" + f2num(now.getSeconds().toString());
    message = $("<div/>").text(message).html();
    message = message.replace("\n", "<br />\n");
    self._logHtml.prepend("[<strong>" + time + "</strong>] " + message + "\n");
    self._logHtml.scrollTop(self._logHtml.prop("scrollHeight"));
}

AdminApp.prototype._clearLogs = function() {
    this._logHtml.empty();
}
