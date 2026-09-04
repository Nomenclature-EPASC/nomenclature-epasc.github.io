const VERSION = "v3";
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

            .catch(function() {

                return caches.match(event.request);

            })

    );

});
