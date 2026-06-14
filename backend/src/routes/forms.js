const express = require("express");
const router = express.Router();
const pool = require("../db");

/* CONTACT FORM */
router.post("/contact", async (req, res) => {
  const { name, email, message } = req.body;

  if (!name || !email || !message) {
    return res.status(400).json({ error: "Заповніть усі поля" });
  }

  try {
    await pool.query(`
      INSERT INTO contact_form_submissions
      (name, email, message, source, created_at)
      VALUES ($1, $2, $3, 'site_contacts', NOW())
    `, [name, email, message]);

    res.status(201).json({ message: "Повідомлення надіслано" });
  } catch (error) {
    console.error("POST /api/forms/contact error:", error);
    res.status(500).json({
      error: "Server error. Перевір, чи існує таблиця contact_form_submissions."
    });
  }
});

/* TEAM APPLICATION */
router.post("/team-application", async (req, res) => {
  const { applicant_name, applicant_contact } = req.body;

  if (!applicant_name || !applicant_contact) {
    return res.status(400).json({ error: "Заповніть обов'язкові поля" });
  }

  try {
    const result = await pool.query(`
      INSERT INTO team_join_applications
      (applicant_name, applicant_contact, status, source, created_at, updated_at)
      VALUES ($1, $2, 'new', 'site', NOW(), NOW())
      RETURNING id, applicant_name, applicant_contact, status, source, created_at
    `, [applicant_name, applicant_contact]);

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error("POST /api/forms/team-application error:", error);
    res.status(500).json({ error: "Server error" });
  }
});

/* SPACE BOOKING */
router.post("/space-booking", async (req, res) => {
  const {
    event_name,
    event_description,
    space_id,
    booking_date,
    start_time,
    end_time,
    contact_name,
    contact_phone,
    contact_email
  } = req.body;

  if (
    !event_name ||
    !space_id ||
    !booking_date ||
    !start_time ||
    !end_time ||
    !contact_name
  ) {
    return res.status(400).json({ error: "Заповніть обов'язкові поля" });
  }

  try {
    const result = await pool.query(`
      INSERT INTO space_booking_requests
      (
        event_name,
        event_description,
        space_id,
        booking_date,
        start_time,
        end_time,
        contact_name,
        contact_phone,
        contact_email,
        status,
        source,
        created_at,
        updated_at
      )
      VALUES
      ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'new', 'site', NOW(), NOW())
      RETURNING id, event_name, booking_date, start_time, end_time, status
    `, [
      event_name,
      event_description || null,
      space_id,
      booking_date,
      start_time,
      end_time,
      contact_name,
      contact_phone || null,
      contact_email || null
    ]);

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error("POST /api/forms/space-booking error:", error);
    res.status(500).json({ error: "Server error" });
  }
});

module.exports = router;