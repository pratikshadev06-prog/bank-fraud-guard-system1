-- ==========================================
-- 1. TABLES CREATION
-- ==========================================

-- Accounts Table
CREATE TABLE Accounts (
    account_id NUMBER PRIMARY KEY,
    customer_name VARCHAR2(100),
    daily_limit NUMBER DEFAULT 50000,
    current_balance NUMBER,
    status VARCHAR2(20) DEFAULT 'ACTIVE' -- ACTIVE, SUSPENDED, BLOCKED
);

-- Transactions Table
CREATE TABLE Transactions (
    txn_id NUMBER PRIMARY KEY,
    account_id NUMBER REFERENCES Accounts(account_id),
    amount NUMBER,
    txn_location VARCHAR2(50),
    txn_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR2(20) -- SUCCESS, BLOCKED
);

-- Fraud_Logs Table
CREATE TABLE Fraud_Logs (
    log_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id NUMBER,
    txn_id NUMBER,
    reason VARCHAR2(200),
    logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- ==========================================
-- 2. TRIGGER (Fraud Guard & Daily Limit)
-- ==========================================

CREATE OR REPLACE TRIGGER trg_fraud_guard
BEFORE INSERT ON Transactions
FOR EACH ROW
DECLARE
    v_daily_total NUMBER := 0;
    v_limit NUMBER;
    v_status VARCHAR2(20);
BEGIN
    -- Account status aur limit fetch karna
    SELECT status, daily_limit INTO v_status, v_limit 
    FROM Accounts WHERE account_id = :NEW.account_id;

    -- Rule 1: Blocked account check
    IF v_status = 'BLOCKED' THEN
        RAISE_APPLICATION_ERROR(-20001, 'Transaction Failed: Account is BLOCKED due to suspicious activity.');
    END IF;

    -- Rule 2: Aaj ke total transactions ka sum nikalna
    SELECT NVL(SUM(amount), 0) INTO v_daily_total 
    FROM Transactions 
    WHERE account_id = :NEW.account_id 
      AND TRUNC(txn_time) = TRUNC(SYSDATE)
      AND status = 'SUCCESS';

    -- Rule 3: Daily Limit Check
    IF (v_daily_total + :NEW.amount) > v_limit THEN
        :NEW.status := 'BLOCKED';
        
        -- Fraud Log mein entry daalna
        INSERT INTO Fraud_Logs (account_id, txn_id, reason)
        VALUES (:NEW.account_id, :NEW.txn_id, 'Daily limit exceeded. Limit: ' || v_limit);
        
        RAISE_APPLICATION_ERROR(-20002, 'Transaction Cancelled: Daily spending limit exceeded.');
    ELSE
        :NEW.status := 'SUCCESS';
        -- Balance update karna
        UPDATE Accounts 
        SET current_balance = current_balance - :NEW.amount 
        WHERE account_id = :NEW.account_id;
    END IF;
END;
/


-- ==========================================
-- 3. FUNCTION (Fraud Risk Score Generator)
-- ==========================================

CREATE OR REPLACE FUNCTION fn_get_fraud_score (
    p_account_id IN NUMBER,
    p_current_location IN VARCHAR2
) RETURN NUMBER IS
    v_score NUMBER := 0;
    v_recent_locations NUMBER := 0;
BEGIN
    -- Check karein ki picchle 10 min mein kitne alag locations se transaction hue hain
    SELECT COUNT(DISTINCT txn_location)
    INTO v_recent_locations
    FROM Transactions
    WHERE account_id = p_account_id
      AND txn_location != p_current_location
      AND txn_time >= SYSDATE - (10 / 1440); -- Last 10 minutes

    IF v_recent_locations >= 1 THEN
        v_score := v_score + 80; -- High risk score for location mismatch
    END IF;

    RETURN v_score;
END;
/


-- ==========================================
-- 4. PACKAGE (Monthly Statement)
-- ==========================================

-- Package Header
CREATE OR REPLACE PACKAGE pkg_bank_management AS
    PROCEDURE generate_monthly_statement(p_account_id IN NUMBER);
END pkg_bank_management;
/

-- Package Body
CREATE OR REPLACE PACKAGE BODY pkg_bank_management AS
    PROCEDURE generate_monthly_statement(p_account_id IN NUMBER) IS
        CURSOR c_txns IS 
            SELECT txn_id, amount, txn_location, txn_time, status 
            FROM Transactions 
            WHERE account_id = p_account_id;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('--- MONTHLY STATEMENT FOR ACCOUNT: ' || p_account_id || ' ---');
        FOR r IN c_txns LOOP
            DBMS_OUTPUT.PUT_LINE('Txn ID: ' || r.txn_id || ' | Amt: ' || r.amount || ' | Loc: ' || r.txn_location || ' | Status: ' || r.status);
        END LOOP;
    END generate_monthly_statement;
END pkg_bank_management;
/


-- ==========================================
-- 5. SAMPLE DATA INSERTION & TESTING
-- ==========================================

-- Test Account Add Karein
INSERT INTO Accounts (account_id, customer_name, daily_limit, current_balance, status) 
VALUES (101, 'Pratiksha Dhiman', 10000, 50000, 'ACTIVE');

COMMIT;

-- Test Transaction (Yeh successfully execute hoga)
INSERT INTO Transactions (txn_id, account_id, amount, txn_location) 
VALUES (1, 101, 2000, 'Pune');

COMMIT;

-- ==========================================
-- 5. SAMPLE DATA INSERTION & TESTING
-- ==========================================

-- A. Test Account Add Karein (Limit: 10,000)
INSERT INTO Accounts (account_id, customer_name, daily_limit, current_balance, status) 
VALUES (101, 'Pratiksha Dhiman', 10000, 50000, 'ACTIVE');

COMMIT;

-- B. Successful Transaction (2,000 ka kharch - Yeh pass hoga)
INSERT INTO Transactions (txn_id, account_id, amount, txn_location) 
VALUES (1, 101, 2000, 'Pune');

COMMIT;

-- C. Monthly Statement Print Karne ke Liye Test
SET SERVEROUTPUT ON;
BEGIN
    pkg_bank_management.generate_monthly_statement(101);
END;
/

-- D. Limit Exceed Test (Agar aap yeh run karengi toh error aayega kyunki limit cross ho rahi hai)
-- INSERT INTO Transactions (txn_id, account_id, amount, txn_location) 
-- VALUES (2, 101, 12000, 'Mumbai');