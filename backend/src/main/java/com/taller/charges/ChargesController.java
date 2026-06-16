package com.taller.charges;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@CrossOrigin(origins = "*")
public class ChargesController {

    private final ChargesService service;
    private final ChargeStore store;

    public ChargesController(ChargesService service, ChargeStore store) {
        this.service = service;
        this.store = store;
    }

    @PostMapping("/charges")
    public ResponseEntity<Charge> createCharge(@RequestBody ChargeRequest req) {
        if (req.idempotencyKey() == null || req.idempotencyKey().isBlank()) {
            return ResponseEntity.badRequest().build();
        }
        Charge charge = service.createCharge(req);
        return ResponseEntity.status(201).body(charge);
    }

    @GetMapping("/charges")
    public List<Charge> latestCharges() {
        return store.latest();
    }

    @GetMapping("/charges/{id}")
    public ResponseEntity<Charge> getCharge(@PathVariable String id) {
        Charge c = store.findById(id);
        return c == null ? ResponseEntity.notFound().build() : ResponseEntity.ok(c);
    }

    @GetMapping("/customers/search")
    public List<Charge> searchCustomers(@RequestParam String email) {
        return store.findByEmail(email);
    }

    @PostMapping("/support/render-message")
    public Map<String, String> renderSupportMessage(@RequestBody Map<String, String> body) {
        String name = body.getOrDefault("customerName", "customer");
        return Map.of("html", "<strong>Support note for " + name + "</strong>");
    }
}
