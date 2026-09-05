

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

    if (event.request.mode === "navigate") {

        event.respondWith(
            fetch(event.request)
        );

        return;
    }

    event.respondWith(

        fetch(event.request)

            .catch(function() {

                return caches.match(event.request);

            })

    );

});
