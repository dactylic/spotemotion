import random
from flask import Flask, render_template, request, redirect, url_for
import spotipy
from spotipy.oauth2 import SpotifyClientCredentials
import genre_modules
from genres import huge_list
import config

app = Flask(__name__)

cid = config.cid
secret = config.secret
SPOTIPY_CLIENT_ID = config.SPOTIPY_CLIENT_ID
SPOTIPY_CLIENT_SECRET = config.SPOTIPY_CLIENT_SECRET
client_credentials_manager = SpotifyClientCredentials(
    client_id=cid, client_secret=secret
)
sp = spotipy.Spotify(client_credentials_manager=client_credentials_manager)


def get_playlist_items(playlist_uri):
    """
    Description:
    Takes in a playlist URI and processes it, extracting each song's genres.
    Input:
    Spotify playlist URI
    Output:
    A list containing the sub-genres of each song as a list.
    Example:
    [["Rock", "RNB", "Rap"], [""post-teen pop", "electropop", "pop rock", "k-pop",]]
    """
    genre_list_list = []
    try:
        for track in sp.playlist_tracks(playlist_uri)["items"]:
            artist_uri = track["track"]["artists"][0]["uri"]
            artist_info = sp.artist(artist_uri)
            artist_genre = artist_info["genres"]
            genre_list_list.append(artist_genre)

    except Exception:
        pass
    genres_listed = [genre for genre_list in genre_list_list for genre in genre_list]
    return genres_listed


# ugly function needs to be refactored to not use nested loops.
def tally(playlist_list):
    """
    Description:
    Processes a list of genres and iterates over each genre that Spotify uses.
    Then it categorizes the sub-genres into larger meta-genres and counts their occurrences.
    Then it returns the dictionary that is each meta-genres count.

    Input:
    List of sub-genres

    Output:
    Dictionary where each key is the meta-genre and the value is how many times
    it occurs in the playlist.
    """
    for sub_genre in huge_list:
        for genre in playlist_list:
            if genre in huge_list[sub_genre]:
                genre_modules.genre_dict[sub_genre] += 1
    return genre_modules.genre_dict


# this function is deprecated. not removing yet but it is not used.
def retrieve():
    """
    Helper function to access the input form.
    """
    msg = request.form["anything"]
    return get_playlist_items(msg)


@app.route("/input")
def generate_moods():
    """
    Routed default /input page. Displays welcome in the message box.
    """
    msg = "Welcome!"
    return render_template("index.html", description=msg)


@app.route("/input/", methods=["GET", "POST"])
def render_descriptors():
    """
    Description:
    Primary function. Retrieves the playlist from the form and raises an error if nothing is sent.
    Splits the submission so we can handle submissions that are playlist URLs instead of URIs.
    Calls tally on get_playlist_items against the URI.
    Sorts the output values and takes the first 3, then retrieves the genres.
    After the most prevalent genres are found, it randomly selects 3 descriptors from
    the list of descriptors for those genres, joins them, and returns the list.

    Input:
    None, this function simply calls the functions it needs to build the objects it requires

    Output:
    Comma joined string of descriptors for the genres of the provided playlist URI

    """
    uri_import = request.form["anything"]
    if not uri_import:
        return render_template("index.html", description="Please enter a valid value.")
    if uri_import[-1] == "/":
        uri_import = uri_import[:-1]
    # take everything after the last slash and before the first question mark
    uri = uri_import.split("/")[-1].split("?")[0]
    # get_playlist_items(uri)
    embed_playlist_string = (
        f"https://open.spotify.com/embed/playlist/{uri}?utm_source=generator&theme=0"
    )
    in_list = tally(get_playlist_items(uri))
    sorted_values = sorted(in_list.values(), reverse=True)[:3]
    sorted_genres = [i[0] for i in in_list.items() if i[1] in sorted_values]
    mood = [random.choice(genre_modules.genre_mood_gen[genre]) for genre in sorted_genres]
    return_message = ", ".join(list(mood)[:3])
    return render_template(
        "index.html", description=return_message, src=embed_playlist_string
    )


@app.route("/about")
def about():
    """
    Basic about page to share our Githubs, although Pen doesn't have one.
    """
    msg = "<a href='github.com/dactylic'>Liam</a> and Pen wrote this."
    msg = msg.split("\n")
    return render_template("about.html", msg=msg)


@app.route("/how-it-works")
def how_it_works():
    """
    Description of how the page works.
    """
    msg = "Your playlist is ingested using its unique url. \n\
        From there, the metadata of the playlist is \
        identified using the Spotify API.\n\
        The genres present in the playlist are analyzed\
        by frequency.\n\
        The analysis associates particular genres with\n\
        phrases and words and then generates\n\
        a set of words describing to your playlist"
    msg = msg.split("\n")
    return render_template("how-it-works.html", msg=msg)


@app.route("/")
def home():
    """
    Redirect from an unprovided endpoint to the /input page.
    """
    return redirect(url_for("generate_moods"))
