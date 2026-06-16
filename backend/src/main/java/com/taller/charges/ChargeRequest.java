package com.taller.charges;

public record ChargeRequest(
        String idempotencyKey,
        double amount,
        String currency,
        String customerEmail,
        String cardToken,
        String description
) {}
