SHELL := /bin/bash

# Java 17 via mise
JAVA_HOME := $(shell mise where java@17 2>/dev/null || mise where java 2>/dev/null)
export JAVA_HOME
export PATH := $(JAVA_HOME)/bin:$(PATH)

MAVEN := $(shell mise which mvn 2>/dev/null || echo mvn)
NPM   := $(shell mise which npm 2>/dev/null || echo npm)

BACK_DIR  := backend
FRONT_DIR := frontend

FRONT_PID_FILE := .front.pid
FRONT_LOG_FILE := .front.log
BACK_PID_FILE  := .back.pid
BACK_LOG_FILE  := .back.log

.PHONY: help \
        back-build back-test back-dev back-stop back-restart back-logs back-status \
        front-install front-dev front-stop front-restart front-logs front-status front-test \
        setup test dev stop restart

help:
	@echo ""
	@echo "  === Backend (Spring Boot — http://localhost:8080) ==="
	@echo "  make back-build     Build JAR sem testes"
	@echo "  make back-test      Roda testes Maven"
	@echo "  make back-dev       Inicia spring-boot:run em background"
	@echo "  make back-stop      Para o backend"
	@echo "  make back-restart   Para e reinicia o backend"
	@echo "  make back-logs      Tail do log do backend"
	@echo "  make back-status    Estado do backend"
	@echo ""
	@echo "  === Frontend (Vite — http://localhost:5173) ==="
	@echo "  make front-install  npm install"
	@echo "  make front-dev      Inicia vite em background"
	@echo "  make front-stop     Para o frontend"
	@echo "  make front-restart  Para e reinicia o frontend"
	@echo "  make front-logs     Tail do log do frontend"
	@echo "  make front-status   Estado do frontend"
	@echo "  make front-test     Roda vitest"
	@echo ""
	@echo "  === Atalhos ==="
	@echo "  make setup          Instala dependências (back + front)"
	@echo "  make test           Roda todos os testes (back + front)"
	@echo "  make dev            Inicia backend + frontend"
	@echo "  make stop           Para backend + frontend"
	@echo "  make restart        Para e reinicia tudo"
	@echo ""

# ---------------------------------------------------------------------------
# Backend
# ---------------------------------------------------------------------------

back-build:
	cd $(BACK_DIR) && $(MAVEN) clean package -T4 -DskipTests

back-test:
	cd $(BACK_DIR) && $(MAVEN) test

back-dev:
	@if [ -f $(BACK_PID_FILE) ] && kill -0 $$(cat $(BACK_PID_FILE)) 2>/dev/null; then \
		echo "Backend já está rodando (PID $$(cat $(BACK_PID_FILE)))"; \
	else \
		setsid bash -c 'cd $(BACK_DIR) && JAVA_HOME=$(JAVA_HOME) PATH=$(JAVA_HOME)/bin:$$PATH $(MAVEN) spring-boot:run >> $(CURDIR)/$(BACK_LOG_FILE) 2>&1' & echo $$! > $(BACK_PID_FILE); \
		echo "Backend iniciado (PID $$(cat $(BACK_PID_FILE))) — log: $(BACK_LOG_FILE)"; \
		echo "API → http://localhost:8080"; \
	fi

back-stop:
	@if [ -f $(BACK_PID_FILE) ]; then \
		PID=$$(cat $(BACK_PID_FILE)); \
		if kill -0 $$PID 2>/dev/null; then \
			kill -- -$$PID && echo "Backend parado (PID $$PID)"; \
		else \
			echo "Backend já estava parado"; \
		fi; \
		rm -f $(BACK_PID_FILE); \
	else \
		echo "Backend: nenhum PID file encontrado"; \
	fi

back-restart: back-stop back-dev

back-status:
	@if [ -f $(BACK_PID_FILE) ] && kill -0 $$(cat $(BACK_PID_FILE)) 2>/dev/null; then \
		echo "Backend: rodando (PID $$(cat $(BACK_PID_FILE)))"; \
	else \
		echo "Backend: parado"; \
	fi

back-logs:
	@touch $(BACK_LOG_FILE)
	@tail -f $(BACK_LOG_FILE)

# ---------------------------------------------------------------------------
# Frontend
# ---------------------------------------------------------------------------

front-install:
	cd $(FRONT_DIR) && $(NPM) install

front-test:
	cd $(FRONT_DIR) && $(NPM) test

front-dev:
	@if [ -f $(FRONT_PID_FILE) ] && kill -0 $$(cat $(FRONT_PID_FILE)) 2>/dev/null; then \
		echo "Frontend já está rodando (PID $$(cat $(FRONT_PID_FILE)))"; \
	else \
		setsid bash -c 'cd $(FRONT_DIR) && $(NPM) run dev >> $(CURDIR)/$(FRONT_LOG_FILE) 2>&1' & echo $$! > $(FRONT_PID_FILE); \
		echo "Frontend iniciado (PID $$(cat $(FRONT_PID_FILE))) — log: $(FRONT_LOG_FILE)"; \
		echo "App → http://localhost:5173"; \
	fi

front-stop:
	@if [ -f $(FRONT_PID_FILE) ]; then \
		PID=$$(cat $(FRONT_PID_FILE)); \
		if kill -0 $$PID 2>/dev/null; then \
			kill -- -$$PID && echo "Frontend parado (PID $$PID)"; \
		else \
			echo "Frontend já estava parado"; \
		fi; \
		rm -f $(FRONT_PID_FILE); \
	else \
		echo "Frontend: nenhum PID file encontrado"; \
	fi

front-restart: front-stop front-dev

front-status:
	@if [ -f $(FRONT_PID_FILE) ] && kill -0 $$(cat $(FRONT_PID_FILE)) 2>/dev/null; then \
		echo "Frontend: rodando (PID $$(cat $(FRONT_PID_FILE)))"; \
	else \
		echo "Frontend: parado"; \
	fi

front-logs:
	@touch $(FRONT_LOG_FILE)
	@tail -f $(FRONT_LOG_FILE)

# ---------------------------------------------------------------------------
# Combined shortcuts
# ---------------------------------------------------------------------------

setup: front-install
	cd $(BACK_DIR) && $(MAVEN) -q dependency:go-offline

test: back-test front-test

dev: back-dev front-dev

stop: back-stop front-stop

restart: stop dev
