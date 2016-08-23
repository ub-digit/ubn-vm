## TODO ##
# Need to normalize Accept and include in Vary!?? How normalize, hard coded to HTML/JSON/XML/Other, or pick first value?
# Check different browers, sniff for "/(x)?html" "/json" "/xml"?

vcl 4.0;

import std;
import directors;

backend ubnext_drupal7 {
  .host = "drupal7.ubnvm.dev"; # IP or Hostname of backend
  .port = "8080";
  .max_connections = 300;
  
  /*
  .probe = {
    #.url = "/sv"; # short easy way (GET /)
    # We prefer to only do a HEAD /
    .request =
      "HEAD /sv HTTP/1.1"
      "Host: drupal7.ubnvm.dev" #???
      "Connection: close"
      "User-Agent: Varnish Health Probe";

    .interval  = 10s; # check the health of each backend every 30 seconds
    .timeout   = 5s; # timing out after 5 seconds.
    .window    = 5;  # If 3 out of the last 5 polls succeeded the backend is considered healthy, otherwise it will be marked as sick
    .threshold = 3;
  }
  */

  .first_byte_timeout     = 300s;   # How long to wait before we receive a first byte from our backend?
  .connect_timeout        = 5s;     # How long to wait for a backend connection?
  .between_bytes_timeout  = 2s;     # How long to wait between bytes received from our backend?
}

# ??
acl purge {
  # ACL we'll use later to allow purges
  "localhost";
  "127.0.0.1";
  "::1";
}

// TODO: Good for protecting againt DDOS etc
/*
acl editors {
  # ACL to honor the "Cache-Control: no-cache" header to force a refresh but only from selected IPs
  "localhost";
  "127.0.0.1";
  "::1";
}
*/

sub vcl_init {
  new vdir = directors.round_robin();
  vdir.add_backend(ubnext_drupal7);
}

# ???
/*
The final way to invalidate an object is a method that allows you to refresh an object by forcing a hash miss for a single request. If you set 'req.hash_always_miss' to true, Varnish will miss the current object in the cache, thus forcing a fetch from the backend. This can in turn add the freshly fetched object to the cache, thus overriding the current one. The old object will stay in the cache until ttl expires or it is evicted by some other means.
*/
# https://www.varnish-cache.org/docs/4.0/users-guide/purging.html

/*
sub vcl_recv {
  if (req.method == "PURGE") {
    if (client.ip !~ purge) {
      return(synth(403, "Not allowed"));
    }
    ban("obj.http.x-url ~ " + req.url); # Assumes req.url is a regex. This might be a bit too simple
  }
}
*/


sub vcl_recv {
  # TODO: check documentation for this, backend_hint?
  set req.backend_hint = vdir.backend();

  # Normalize host header
  # TODO: ENABLE AND TEST THIS
  
  # normalize www or without www
  # set req.http.host = regsub(req.http.host, "^www\.", "");

  # Remove port
  set req.http.Host = regsub(req.http.Host, ":[0-9]+", "");

  # Normalize the query arguments
  set req.url = std.querysort(req.url);

  # Normalize Accept
  if(req.http.Accept) {
    if(req.http.Accept ~ "^\w+/x?html *[,;]") {
      unset req.http.Accept;
    }
    else if(req.http.Accept ~ "^\w+/xml *[,;]") {
      set req.http.Accept = "application/xml";
    }
    else if(req.http.Accept ~ "^\w+/json *[,;]") {
      set req.http.Accept = "application/json";
    }
    else {
      set req.http.Accept = regsub(req.http.Accept, " *[,;].*", "");
    }
  }

  # Normalize Accept-Lanugage
  # For now we just unset this
  if(req.http.Accept-Language) {
    unset req.http.Accept-Language;
  }

  # Strip hash, server doesn't need it. (Or does varnish do this)
  if (req.url ~ "\#") {
    set req.url = regsub(req.url, "\#.*$", "");
  }

  #TODO: Cache-Control: private in drupal?

  if (req.restarts == 0) {
     # normalize Accept-Encoding to reduce vary
     # support deflate?
    if (req.http.Accept-Encoding ~ "gzip" && req.http.User-Agent !~ "MSIE 6") {
      set req.http.Accept-Encoding = "gzip";
    } else {
      unset req.http.Accept-Encoding;
    }
  }

  # Allow purging (Don't think we need this since controlport will be used)
  if (req.method == "PURGE") {
    if (!client.ip ~ purge) { # purge is the ACL defined at the begining
      # Not from an allowed IP? Then die with an error.
      return (synth(405, "This IP is not allowed to send PURGE requests."));
    }
    # If you got this stage (and didn't error out above), purge the cached result
    return (purge);
  }

  if (req.http.Cache-Control ~ "(?i)no-cache") {
  #if (req.http.Cache-Control ~ "(?i)no-cache" && client.ip ~ editors) { # create the acl editors and uncomment this if you want to restrict the Ctrl-F5
    # Ignore requests via proxy caches, IE users and badly behaved crawlers like msnbot that send no-cache with every request.
    # TODO: understand how http.X-Purge works and comes into play
    if (! (req.http.Via || req.http.User-Agent ~ "bot|MSIE" || req.http.X-Purge)) {
      // TODO: Difference from ban? Arbitary?
      # ttl is now read only, replace with beresp ttl
      return (purge);  # Couple this with restart in vcl_purge and X-Purge header to avoid loops
    }
  }

  # Allow the backend to serve up stale content if it is responding slowly.
  # TODO: Does not work anymore, refactor for varnish 4.0, beresp.grace settable in vcl_backend_response (and vcl_backend_error)
  #if (std.healthy(req.backend_hint)) {
  #  set req.grace = 30s;
  #} else {
  #  set req.grace = 24h;
    # Use anonymous, cached pages if all backends are down.
  #  unset req.http.Cookie;
  #}

  if (req.restarts == 0) {
    if (req.http.x-forwarded-for) {
      set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
    }
    else {
      set req.http.X-Forwarded-For = client.ip;
    }
  }

  # This is a nifty trick
  if (req.method == "POST") {
    ban("req.http.x-url = " + req.http.Referer);
    return (pass);
  }

  # Implementing websocket support (https://www.varnish-cache.org/docs/4.0/users-guide/vcl-example-websockets.html)
  if (req.http.Upgrade ~ "(?i)websocket") {
    return (pipe);
  }
 
  if (req.method != "GET" && req.method != "HEAD") {
      /* We only deal with GET and HEAD by default */
     if (req.method == "PUT" ||
         req.method == "POST" ||
         req.method == "TRACE" ||
         req.method == "OPTIONS" ||
         req.method == "DELETE") {
       return (pass);
     }
     /* Non-RFC2616 or CONNECT which is weird. */
     return (pipe);
  }
 
  # Do not cache these paths.
  if (req.url ~ "^.*/ajax/.*$" ||
      req.url ~ "^.*/ahah/.*$") {
    return (pass);
  }
  # Do not cache ajax requests
  # TODO: How safe is X-Requested-With header? Probably not all that safe
  # TODO: Improve!!
  if(req.http.X-Requested-With  ~ "(?i)xmlhttprequest") {
    return (pass);
  }

  #Development exception:
  if (req.url ~ "(?i)\.(css|js)(\?.*)?$") {
    return (pass);
  }
 
  # Always cache the following file types for all users. This list of extensions
  # appears twice, once here and again in vcl_backend_response so make sure you edit both
  # and keep them equal.
  # TODO: add exception for private files!!
  if (req.url ~ "(?i)\.(pdf|asc|dat|txt|doc|xls|ppt|csv|png|gif|jpeg|jpg|ico|css|js)(\?.*)?$") {
    unset req.http.Cookie;
    unset req.http.Set-Cookie;
    # TODO: check default vanrnish vcl
    return (hash);
  }
  # TODO: check this regexp, looks weird (^??)
  else if(req.url ~ "^(/sites/[^/]+/files/)") {
    # Probably too large, could be video-stream, zip, tgz etc, so we pipe to be safe
    return (pipe);
  }

  # Send Surrogate-Capability headers to announce ESI support to backend
  set req.http.Surrogate-Capability = "key=ESI/1.0";

  if (req.http.Authorization) {
    # Not cacheable by default
    return (pass);
  }

  if (req.http.Set-Cookie) {
    return (pass);
  }

  # Remove all cookies that Drupal doesn't need to know about. We explicitly
  # list the ones that Drupal does need, the SESS and NO_CACHE. If, after
  # running this code we find that either of these two cookies remains, we
  # will pass as the page cannot be cached.
  
  # The reason we check for the session or NO_CACHE cookies here, and not just replace
  # anything but the session cookie and then check for an empty cookie, is that
  # there are other "useful" cookies set by drupal (has_js for example)
  # that would otherwise be unnecessarily stripped
  # TODO: keep, has_js and add to hash? Yes, probably
  if (req.http.Cookie) {
    if(req.http.Cookie !~ "(;|^) *S{1,2}ESS[a-z0-9]+|NO_CACHE=") {
      # has_js should be safe and not affect hit-rate since should be set in 99.9% of cases?
      if(req.http.Cookie ~ "(;|^) *has_js=1") {
        set req.http.Cookie = "has_js=1";
      }
      else {
        unset req.http.Cookie;
      }
    }
    else {
      return (pass);
    }
  }
  return (hash);
}



sub vcl_pipe {
  # Called upon entering pipe mode.
  # In this mode, the request is passed on to the backend, and any further data from both the client
  # and backend is passed on unaltered until either end closes the connection. Basically, Varnish will
  # degrade into a simple TCP proxy, shuffling bytes back and forth. For a connection in pipe mode,
  # no other VCL subroutine will ever get called after vcl_pipe.

  # Note that only the first request to the backend will have
  # X-Forwarded-For set.  If you use X-Forwarded-For and want to
  # have it set for all requests, make sure to have:
  # set bereq.http.connection = "close";
  # here.  It is not set by default as it might break some broken web
  # applications, like IIS with NTLM authentication.

  # set bereq.http.Connection = "Close";

  # Implementing websocket support (https://www.varnish-cache.org/docs/4.0/users-guide/vcl-example-websockets.html)
  if (req.http.upgrade) {
    set bereq.http.upgrade = req.http.upgrade;
  }

  return (pipe);
}

sub vcl_hash {
  # Difference from using Vary?
  # Called after vcl_recv to create a hash value for the request. This is used as a key
  # to look up the object in Varnish.

  hash_data(req.url);

  if (req.http.host) {
    hash_data(req.http.host);
  } else {
    hash_data(server.ip);
  }

  # hash cookies for requests that have them
  if (req.http.Cookie) {
    hash_data(req.http.Cookie);
  }

  set req.http.X-Varnish-Cacheable = "1";

  return (lookup);
}

# Set a header to track a cache HIT/MISS.
sub vcl_deliver {

  # TODO: this is unset elsewhere, remove? 
  unset resp.http.x-url;
  unset resp.http.x-host;

  if (obj.hits > 0) {
    set resp.http.X-Varnish-Cache = "HIT";
    set resp.http.X-Varnish-Hits = obj.hits;
  }
  else {
    set resp.http.X-Varnish-Cache = "MISS";
  }

  # Remove some headers: PHP version
  unset resp.http.X-Powered-By;
  
  # Remove some headers: Apache version & OS
  # unset resp.http.Server;
  # unset resp.http.X-Drupal-Cache;
  # unset resp.http.X-Varnish;
  # unset resp.http.Via;
  # unset resp.http.Link;
  # unset resp.http.X-Generator;

  if(resp.http.X-Varnish-Reset-Age) {
    /* Remove the magic marker */
    unset resp.http.X-Varnish-Reset-Age;

    /* By definition we have a fresh object */
    set resp.http.Age = "0";
  }

  return (deliver);
}

# TODO: understand what happens here
# TODO: check varnish default vcl
sub vcl_purge {
  # Only handle actual PURGE HTTP methods, everything else is discarded
  if (req.method != "PURGE") {
    # restart request
    set req.http.X-Purge = "Yes";
    return(restart);
  }
}

sub vcl_synth {
  if (resp.status == 720) {
    # We use this special error status 720 to force redirects with 301 (permanent) redirects
    # To use this, call the following from anywhere in vcl_recv: return (synth(720, "http://host/new.html"));
    set resp.http.Location = resp.reason;
    set resp.status = 301;
    return (deliver);
  } elseif (resp.status == 721) {
    # And we use error status 721 to force redirects with a 302 (temporary) redirect
    # To use this, call the following from anywhere in vcl_recv: return (synth(720, "http://host/new.html"));
    set resp.http.Location = resp.reason;
    set resp.status = 302;
    return (deliver);
  }

  return (deliver);
}

 
sub vcl_backend_response {
  #TODO: Fix when saintmode vmod is ready
  /*
  if (beresp.status == 500) {
    set beresp.saintmode = 60s;
    if(bereq.method != "GET" && bereq.method != "HEAD") {
      error 500 "Failed!"; #TODO: change this message?
    } else {
      return(restart);
    }
  }
  */

  # TODO: Read up on grace, difference between beresp.grace and req.grace??
  # Keep this object for 24 hours past it's expiration date
  set beresp.grace = 24h;

  # Because of strange reasons (lurker can't access url or host, since they are not stored in the internal object)
  set beresp.http.x-url = bereq.url;
  set beresp.http.x-host = bereq.http.host;

  # We need this to cache 404s, 301s, 500s. Otherwise, depending on backend but
  # definitely in Drupal's case these responses are not cacheable by default.
  # TODO: verify this works
  if (beresp.status == 404 || beresp.status == 301) {
    set beresp.ttl = 10m;
    return (deliver);
  }
  # Don't allow static files to set cookies.
  # (?i) denotes case insensitive in PCRE (perl compatible regular expressions).
  # This list of extensions appears twice, once here and again in vcl_recv so
  # make sure you edit both and keep them equal.
  if (bereq.url ~ "(?i)\.(pdf|asc|dat|txt|doc|xls|ppt|csv|png|gif|jpeg|jpg|ico|css|js)(\?.*)?$") {
    # TODO: varnish headers case insensitive?
    unset beresp.http.Set-Cookie;
  }

  # Allow items to be stale if needed.
  set beresp.grace = 6h;

  # From default.vcl (modified)
  # Defaults are probably a bad idea (at least in drupal)?
  if (
      #beresp.ttl <= 0s || #?? #TODO: Check what ttl drupal sends by default TODO: how is this set? By varnish?
      beresp.http.Set-Cookie ||
      beresp.http.Vary == "*" ||
      beresp.http.X-Varnish-Cacheable == "0"
    ) { #TODO: Check what drupal sets vary to
    /*
    * Mark as "Hit-For-Pass" for the next 2 minutes
    * Means that the oject will be cached so that vlc_recieve
    * can directly pass hits for this object
    */
    //TODO: Set longer TTL?
    //TODO: this is duplicate code, check below
    set beresp.uncacheable = true;
    set beresp.ttl = 120 s;
    set beresp.http.Varnish-Hit-For-Pass = "1";
    return (deliver);
  }

  # Longer caching

  # RFC2616 specifies an algorithm in section 13.2.4 which combines expires and max-age,
  # and then picks the earlier of the two resulting deadlines, therefore we must unset expire
  # for max-age to take precedence.
  # Also, we don't really care about any "expires" Drupal sets since cache is purged explicitly from the backend

  if(bereq.http.X-Varnish-Cacheable) {

    unset beresp.http.expires;

    # Set the clients TTL on this object (we should probably not set thisk, or only for css etc?)
    # TODO: check drupal defaults?
    # TODO: Varnish respects this?
    set beresp.http.Cache-Control = "max-age=0";

    # Set how long Varnish will keep it
    # Allow backend to override varnish TTL
    if (beresp.http.X-Varnish-TTL) {
      set beresp.ttl = std.duration(beresp.http.X-Varnish-TTL + "s", 0s);
      # TODO: Uncomment this after verifying this feature works
      #unset beresp.http.X-Varnish-TTL;
    }
    else {
      set beresp.ttl = 1w;
    }

    # marker for vcl_deliver to reset Age:
    # TODO: Don't like "magicmarker", rename to something less arbitary
    set beresp.http.X-Varnish-Reset-Age = "1";
  }
   return (deliver);
}

# In the event of an error, show friendlier messages.
sub vcl_backend_error {
  # Redirect to some other URL in the case of a homepage failure.
  #if (req.url ~ "^/?$") {
  #  set obj.status = 302;
  #  set obj.http.Location = "http://backup.example.com/";
  #}

  # TODO: Prettify this 
  # TODO: Varnish 4:fy this
  # See vlc_synth
  # resp.http.Content-Type = "text/html; charset=utf-8";
  /*
  synthetic("
<html>
<head>
  <title>Page Unavailable</title>
  <style>
    body { background: #303030; text-align: center; color: white; }
    #page { border: 1px solid #CCC; width: 500px; margin: 100px auto 0; padding: 30px; background: #323232; }
    a, a:link, a:visited { color: #CCC; }
    .error { color: #222; }
  </style>
</head>
<body onload="setTimeout(function() { window.location = '/' }, 50000)">
  <div id="page">
    <h1 class="title">Page Unavailable</h1>
    <p>The page you requested is temporarily unavailable.</p>
    <p>We're redirecting you to the <a href="/">homepage</a> in 5 seconds.</p>
    <div class="error">(Error "} + obj.status + " " + obj.response + {")</div>
  </div>
</body>
</html>
");
*/
  #return (deliver);
}


#TODO: compare with varnish default
sub vcl_hit {
  
  if (obj.ttl >= 0s) {
    # A pure unadultered hit, deliver it
    return (deliver);
  }

  # https://www.varnish-cache.org/docs/trunk/users-guide/vcl-grace.html
  # When several clients are requesting the same page Varnish will send one request to the backend and place the others on hold while fetching one copy from the backend. In some products this is called request coalescing and Varnish does this automatically.
  # If you are serving thousands of hits per second the queue of waiting requests can get huge. There are two potential problems - one is a thundering herd problem - suddenly releasing a thousand threads to serve content might send the load sky high. Secondly - nobody likes to wait. To deal with this we can instruct Varnish to keep the objects in cache beyond their TTL and to serve the waiting requests somewhat stale content.

  # if (!std.healthy(req.backend_hint) && (obj.ttl + obj.grace > 0s)) {
  #   return (deliver);
  # } else {
  #   return (fetch);
  # }

}


# Handle the HTTP request coming from our backend
sub vcl_backend_response {
  # Called after the response headers has been successfully retrieved from the backend.

  # Pause ESI request and remove Surrogate-Control header
  if (beresp.http.Surrogate-Control ~ "ESI/1.0") {
    unset beresp.http.Surrogate-Control;
    set beresp.do_esi = true;
  }

  # Enable cache for all static files
  # The same argument as the static caches from above: monitor your cache size, if you get data nuked out of it, consider giving up the static file cache.
  # Before you blindly enable this, have a read here: https://ma.ttias.be/stop-caching-static-files/
  if (bereq.url ~ "^[^?]*\.(bmp|bz2|css|doc|eot|flv|gif|gz|ico|jpeg|jpg|js|less|mp[34]|pdf|png|rar|rtf|swf|tar|tgz|txt|wav|woff|xml|zip|webm)(\?.*)?$") {
    unset beresp.http.set-cookie;
  }

  # Large static files are delivered directly to the end-user without
  # waiting for Varnish to fully read the file first.
  # Varnish 4 fully supports Streaming, so use streaming here to avoid locking.
  if (bereq.url ~ "^[^?]*\.(mp[34]|rar|tar|tgz|gz|wav|zip|bz2|xz|7z|avi|mov|ogm|mpe?g|mk[av]|webm)(\?.*)?$") {
    unset beresp.http.set-cookie;
    set beresp.do_stream = true;  # Check memory usage it'll grow in fetch_chunksize blocks (128k by default) if the backend doesn't send a Content-Length header, so only enable it for big objects
    set beresp.do_gzip = false;   # Don't try to compress it for storage
  }

  # Sometimes, a 301 or 302 redirect formed via Apache's mod_rewrite can mess with the HTTP port that is being passed along.
  # This often happens with simple rewrite rules in a scenario where Varnish runs on :80 and Apache on :8080 on the same box.
  # A redirect can then often redirect the end-user to a URL on :8080, where it should be :80.
  # This may need finetuning on your setup.
  #
  # To prevent accidental replace, we only filter the 301/302 redirects for now.
  if (beresp.status == 301 || beresp.status == 302) {
    set beresp.http.Location = regsub(beresp.http.Location, ":[0-9]+", "");
  }

  # Set 2min cache if unset for static files
  if (beresp.ttl <= 0s || beresp.http.Set-Cookie || beresp.http.Vary == "*") {
    set beresp.ttl = 120s; # Important, you shouldn't rely on this, SET YOUR HEADERS in the backend
    set beresp.uncacheable = true;
    return (deliver);
  }

  # Allow stale content, in case the backend goes down.
  # make Varnish keep all objects for 6 hours beyond their TTL
  set beresp.grace = 6h;

  return (deliver);
}

