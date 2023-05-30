from flask import Flask, render_template, abort, jsonify, request, redirect, url_for, session
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobClient
from werkzeug.utils import secure_filename
from time import sleep
import os
from functools import wraps
import pyodbc

app = Flask(__name__)
# THIS IS NOT A GOOD PRACTICE DON'T EVER DO THIS IN PROD
app.secret_key = os.urandom(12)

def config_db(connString:str):
    with pyodbc.connect(connString) as conn:
        with conn.cursor() as cursor:
            cursor.execute('''
                IF NOT EXISTS(SELECT name FROM sys.tables WHERE name = 'Persons')
                    BEGIN
                        CREATE TABLE Persons (
                            id int,
                            name varchar(255),
                            email varchar(255),
                            favorite_color varchar(255),
                            password varchar(255),
                            ssn varchar(255)
                        )

                        INSERT INTO Persons (id, name, email, favorite_color, password, ssn)
                        VALUES
                        (1, 'alice', 'alice@contoso.com', 'red', '@$8gs9asdf', '123-39-2931'),
                        (2, 'bob', 'bob@contoso.com', 'orange', 'aujv842$2', '867-53-0912'),
                        (3, 'charles', 'charles@contoso.com', 'yellow', '4829572!', '042-43-0000'),
                        (4, 'dave', 'dave@contoso.com', 'green', 'weakpass', '666-85-9876'),
                        (5, 'emily', 'emily@contoso.com', 'blue', '1234qwer', '323-28-2392'),
                        (6, 'felix', 'felix@contoso.com', 'indigo', 'letmein', '666-00-4895'), 
                        (7, 'georgette', 'georgette@contoso.com', 'violet', '8675309', '223-99-1234')
                    END
            ''')
            cursor.commit()


if 'WEBSITE_HOSTNAME' in os.environ:
    storage_url = os.environ['APPSETTING_storage_url']
    storage_container = os.environ['APPSETTING_storage_container']
    connString = os.environ['SQLAZURECONNSTR_DefaultConnection']
    config_db(connString)
    init = True

@app.route("/")
def welcome(*args, **kwargs):
    if not init:
        return render_template("welcome.html", message="uninititiated")
    
    return render_template("welcome.html")

@app.route("/initialize", methods=["GET", "POST"])
def initialize():
    if request.method == 'POST':
        session['config'] = {
            "storage_url" : request.form['storagename'],
            "container" : request.form['containername'],
            "sql_server" : request.form['sqlserver'],
            "database" : request.form['database'],
            "databaseuser" : request.form['databaseuser'],
            "databasepassword" : request.form['databasepassword'],
        }

        # Populate the DB with bogus users and info
        # Again... another horrible practice, don't do this in prod
        connString = "Driver={ODBC Driver 17 for SQL Server};Server=tcp:"+session['config']['sql_server']+",1433;Database="+session['config']['database']+";Uid="+session['config']['databaseuser']+";Pwd="+session['config']['databasepassword']+";Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
        with pyodbc.connect(connString) as conn:
            with conn.cursor() as cursor:
                cursor.execute('''
                    IF NOT EXISTS(SELECT name FROM sys.tables WHERE name = 'Persons')
                        BEGIN
                            CREATE TABLE Persons (
                                id int,
                                name varchar(255),
                                email varchar(255),
                                favorite_color varchar(255),
                                password varchar(255),
                                ssn varchar(255)
                            )

                            INSERT INTO Persons (id, name, email, favorite_color, password, ssn)
                            VALUES
                            (1, 'alice', 'alice@contoso.com', 'red', '@$8gs9asdf', '123-39-2931'),
                            (2, 'bob', 'bob@contoso.com', 'orange', 'aujv842$2', '867-53-0912'),
                            (3, 'charles', 'charles@contoso.com', 'yellow', '4829572!', '042-43-0000'),
                            (4, 'dave', 'dave@contoso.com', 'green', 'weakpass', '666-85-9876'),
                            (5, 'emily', 'emily@contoso.com', 'blue', '1234qwer', '323-28-2392'),
                            (6, 'felix', 'felix@contoso.com', 'indigo', 'letmein', '666-00-4895'), 
                            (7, 'georgette', 'georgette@contoso.com', 'violet', '8675309', '223-99-1234')
                        END
                ''')
                cursor.commit()


        return redirect(url_for("welcome"))
    
    return render_template("initialize.html")

# def init_required(f):
#     @wraps(f)
#     def decorated_function(*args, **kwargs):
#         if not session.get("config"):
#             return redirect(url_for("initialize"))
#         return f(*args, **kwargs)
#     return decorated_function

@app.route("/users", methods=["GET", "POST"])
#@init_required
def users_view():
    #connString = "Driver={ODBC Driver 17 for SQL Server};Server=tcp:"+session['config']['sql_server']+",1433;Database="+session['config']['database']+";Uid="+session['config']['databaseuser']+";Pwd="+session['config']['databasepassword']+";Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
    with pyodbc.connect(connString) as conn:
        with conn.cursor() as cursor:
            query = "SELECT name FROM Persons"
            cursor.execute(query)
            result = cursor.fetchall()
    return render_template("users.html", users=result)

@app.route("/search_user", methods=["GET", "POST"])
#@init_required
def search_user():
    print('in search')
    #connString = "Driver={ODBC Driver 17 for SQL Server};Server=tcp:"+session['config']['sql_server']+",1433;Database="+session['config']['database']+";Uid="+session['config']['databaseuser']+";Pwd="+session['config']['databasepassword']+";Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
    with pyodbc.connect(connString) as conn:
        with conn.cursor() as cursor:
            # This is where you can inject code into.  We take input from the user and are not sanitizing it or using parameterized queries.  This is a very bad practice.  
            query = f"SELECT id, name, email, favorite_color FROM Persons WHERE name = '{request.form['name']}';"
            print('DEBUG: '+query)
            cursor.execute(query)
            result = cursor.fetchall()
    return redirect(url_for('user_view', result=result))

@app.route('/user_view/<string:result>')
#@init_required
def user_view(result):
    return result

@app.route('/upload', methods=["GET","POST"])
#@init_required
def upload():
    def get_scan_results(blob_client: BlobClient):
        count = 0
        tags = blob_client.get_blob_tags()
        while True and count < 30:
            if 'Malware Scanning scan result' in tags.keys():
                match tags['Malware Scanning scan result']:
                    case 'No threats found':
                        return True, tags
                    case _:
                        return False, tags
            else:
                sleep(1)
                count+=1
                tags = blob_client.get_blob_tags()
        return False, "Sorry, the file you sent was large and exceeded this apps timeout"
            
    if request.method == 'POST':

        f = request.files['file']
        blob_client = BlobClient(
            account_url=session['config']['storage_url'],
            container_name=session['config']['container'],
            blob_name= secure_filename(f.filename) if not 'usesystemmalware' in request.form.keys() else 'eicar.txt',
            credential=DefaultAzureCredential()
        )

    
        upload_return = blob_client.upload_blob(data=secure_filename(f.filename) if not 'usesystemmalware' in request.form.keys() else b"X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*", 
                                                overwrite=True)       
        malware_scan_results, tags = get_scan_results(blob_client=blob_client)
        
        return redirect(url_for('file_details',
                                 filename=secure_filename(f.filename) if not 'usesystemmalware' in request.form.keys() else 'eicar.txt',
                                 details=upload_return,
                                 malware_results=malware_scan_results,
                                 tags=tags))
    else:
        return render_template('upload.html')
    
@app.route('/file_details', methods=["GET", "POST"])
#@init_required
def file_details():
    return render_template('file_details.html', 
                           filename=request.args.get('filename'), 
                           details=request.args.get('details'),
                           malware_results=request.args.get('malware_results'),
                           tags=request.args.get('tags'))

