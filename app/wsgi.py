from app import app as my_app
from waitress import serve

if __name__ == "__main__":
    serve(my_app, listen="*:5000")