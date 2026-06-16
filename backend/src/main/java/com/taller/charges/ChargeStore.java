package com.taller.charges;

import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.logging.Logger;

@Component
public class ChargeStore {
    private static final Logger log = Logger.getLogger(ChargeStore.class.getName());

    private final ConcurrentHashMap<String, Charge> byKey = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, Charge> byId  = new ConcurrentHashMap<>();
    private final CopyOnWriteArrayList<Charge> all        = new CopyOnWriteArrayList<>();

    public Charge findByKey(String key) {
        return byKey.get(key);
    }

    /**
     * Returns null if saved successfully, or the pre-existing charge if the key
     * was already present (concurrent duplicate detected).
     */
    public Charge saveIfAbsent(String key, Charge charge) {
        Charge existing = byKey.putIfAbsent(key, charge);
        if (existing == null) {
            byId.put(charge.id(), charge);
            all.add(charge);
        }
        return existing;
    }

    public Charge findById(String id) {
        return byId.get(id);
    }

    public List<Charge> latest() {
        return all.stream().toList();
    }

    public List<Charge> findByEmail(String email) {
        List<Charge> results = new ArrayList<>();
        for (Charge c : all) {
            if (c.customerEmail().contains(email) || c.customerEmail().equalsIgnoreCase(email)) {
                results.add(c);
            }
        }
        return results;
    }
}
