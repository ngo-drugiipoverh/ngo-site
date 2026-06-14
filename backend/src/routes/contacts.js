const express = require("express");
const pool = require("../db");

const router = express.Router();

router.post("/", async (req, res) => {
  try {
    const {
      sender_name,
      sender_email,
      sender_phone,
      message_text
    } = req.body;

    if (!sender_name || !message_text) {
      return res.status(400).json({
        error: "Ім’я та повідомлення обов’язкові"
      });
    }

    const result = await pool.query(
      `
      INSERT INTO contact_form_submissions
      (
        sender_name,
        sender_email,
        sender_phone,
        message_text,
        source,
        ip_address,
        created_at
      )
      VALUES
      ($1,$2,$3,$4,$5,$6,NOW())
      RETURNING *
      `,
      [
        sender_name,
        sender_email || null,
        sender_phone || null,
        message_text,
        "site_contacts",
        req.ip || null
      ]
    );

    res.status(201).json(result.rows[0]);

  } catch (error) {
    console.error(error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.post("/team-join", async (req, res) => {
  try {
    const {
      name,
      phone,
      email,
      direction,
      motivation,
      links
    } = req.body;

    if (!name || !phone || !direction || !motivation) {
      return res.status(400).json({
        error: "Заповни обов’язкові поля"
      });
    }

    const messageText =
`ЗАЯВКА НА ДОЛУЧЕННЯ ДО КОМАНДИ

Напрям:
${direction}

Мотивація:
${motivation}

Посилання:
${links || "—"}`;

    const result = await pool.query(
      `
      INSERT INTO contact_form_submissions
      (
        sender_name,
        sender_email,
        sender_phone,
        message_text,
        source,
        ip_address,
        created_at
      )
      VALUES
      ($1,$2,$3,$4,$5,$6,NOW())
      RETURNING *
      `,
      [
        name,
        email || null,
        phone,
        messageText,
        "site_contacts",
        req.ip || null
      ]
    );

    res.status(201).json(result.rows[0]);

  } catch (error) {
    console.error(error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.get("/", async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT *
      FROM contact_form_submissions
      ORDER BY created_at DESC
    `);

    res.json(result.rows);

  } catch (error) {
    console.error(error);

    res.status(500).json({
      error: error.message
    });
  }
});

router.delete("/:id", async (req, res) => {
  try {
    await pool.query(
      `
      DELETE FROM contact_form_submissions
      WHERE id = $1
      `,
      [req.params.id]
    );

    res.json({
      success: true
    });

  } catch (error) {
    console.error(error);

    res.status(500).json({
      error: error.message
    });
  }
});

module.exports = router;