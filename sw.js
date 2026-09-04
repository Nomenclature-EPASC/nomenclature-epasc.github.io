const VERSION = "v2";
const CACHE_NAME = "nomenclature-" + VERSION;

self.addEventListener("install", function(event) {

    self.skipWaiting();

});

self.addEventListener("activate", function(event) {

    event.waitUntil(

        caches.keys().then(function(cacheNames) {

            return Promise.all(

                cacheNames
                    .filter(function(cacheName) {
                        return cacheName.startsWith("nomenclature-");
                    })
                    .filter(function(cacheName) {
                        return cacheName !== CACHE_NAME;
                    })
                    .map(function(cacheName) {
                        return caches.delete(cacheName);
                    })

            );

        }).then(function() {

            return self.clients.claim();

        })

    );

});

self.addEventListener("fetch", function(event) {

    event.respondWith(

        fetch(event.request)
            .then(function(response) {

                if (
                    response.ok &&
                    event.request.method === "GET"
                ) {

                    const responseClone =
                        response.clone();

                    caches.open(CACHE_NAME).then(function(cache) {

                        cache.put(
                            event.request,
                            responseClone
                        );

                    });

                }

                return response;

            })
            .catch(function() {

                return caches.match(event.request);

            })

    );

});
