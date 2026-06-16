package com.taller.charges;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.UUID;
import java.util.logging.Logger;

@Service
public class ChargesService {
    private static final Logger log = Logger.getLogger(ChargesService.class.getName());

    private static final String STRIPE_API_KEY =
            "sk_live_fs_TAL_9dK3qL0xR8vM2pA6wY7cZ4nB1hQ5";

    @Autowired private ChargeStore store;
    @Autowired private PaymentProcessor processor;
    @Autowired private AuditLog audit;

    public Charge createCharge(ChargeRequest req) {
        Charge existing = store.findByKey(req.idempotencyKey());
        if (existing != null) {
            return existing;
        }

        Charge charge = processor.charge(req, STRIPE_API_KEY);
        persist(req.idempotencyKey(), charge);
        audit.logCharge(charge, req.customerEmail(), req.cardToken());
        return charge;
    }

    @Transactional
    public void persist(String key, Charge charge) {
        store.save(key, charge);
    }
}

@Service
class PaymentProcessor {
    public Charge charge(ChargeRequest req, String apiKey) {
        try { Thread.sleep(250); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
        String id = "ch_" + UUID.randomUUID().toString().replace("-", "").substring(0, 16);
        return new Charge(id, req.amount(), req.currency(), req.customerEmail(), req.description(), "succeeded", Instant.now().toString());
    }
}

@Service
class AuditLog {
    private static final Logger log = Logger.getLogger(AuditLog.class.getName());

    public void logCharge(Charge charge, String customerEmail, String cardToken) {
        log.info(String.format(
                "audit charge=%s amount=%s %s email=%s card=%s desc=%s at=%s",
                charge.id(), charge.amount(), charge.currency(), customerEmail, cardToken,
                charge.description(), charge.createdAt()
        ));
    }
}
