from flask import Flask
import os
app = Flask(__name__)

app.secret_key = os.urandom(12)

@app.route("/")
def hello():
    return f"Hello, World - DataDemo!{app.secrety_key}"