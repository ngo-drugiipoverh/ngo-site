-- ============================================================
-- БД Інформаційної системи ГО "Олександрійська молодь"
-- Сайт + Адмін-платформа + Телеграм-бот
-- PostgreSQL 15+
-- 47 таблиць · 528+ полів · Повна схема
-- ============================================================

-- ============================================================
-- 1. РОЗШИРЕННЯ
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";      -- Генерація UUID v4
CREATE EXTENSION IF NOT EXISTS "pgcrypto";        -- Шифрування даних
CREATE EXTENSION IF NOT EXISTS "pg_trgm";         -- Пошук по тексту (триграми)

-- ============================================================
-- 2. ПЕРЕРАХУВАННЯ (ENUM TYPES)
-- ============================================================

CREATE TYPE event_status AS ENUM ('draft', 'published', 'cancelled', 'completed');

CREATE TYPE registration_status AS ENUM ('registered', 'confirmed', 'cancelled', 'waitlisted');

CREATE TYPE registration_source AS ENUM ('bot', 'platform_manual');

CREATE TYPE feedback_source AS ENUM ('bot', 'site');

CREATE TYPE message_status AS ENUM ('new', 'viewed', 'replied');

CREATE TYPE broadcast_audience AS ENUM ('all', 'event', 'level');

CREATE TYPE broadcast_status AS ENUM ('draft', 'scheduled', 'sending', 'sent', 'failed');

CREATE TYPE delivery_status AS ENUM ('pending', 'delivered', 'failed');

CREATE TYPE scheduler_trigger AS ENUM ('event_publish', 'cron', 'time_before_event', 'time_after_event', 'user_register');

CREATE TYPE scheduler_audience AS ENUM ('all', 'registered', 'new_users');

CREATE TYPE scheduler_run_status AS ENUM ('triggered', 'sending', 'completed', 'failed');

CREATE TYPE application_status AS ENUM ('new', 'reviewing', 'accepted', 'rejected');

CREATE TYPE question_type AS ENUM ('text', 'select', 'multiselect', 'textarea');

CREATE TYPE booking_status AS ENUM ('new', 'reviewing', 'confirmed', 'rejected');

CREATE TYPE publication_status AS ENUM ('draft', 'published', 'scheduled', 'hidden');

CREATE TYPE project_status AS ENUM ('active', 'completed', 'paused');

CREATE TYPE library_item_type AS ENUM ('book', 'board_game', 'ps5_game');

CREATE TYPE availability_status AS ENUM ('available', 'borrowed', 'unavailable');

CREATE TYPE invitation_status AS ENUM ('pending', 'accepted', 'expired', 'revoked');

CREATE TYPE notification_type AS ENUM (
    'event_new', 'event_cancel', 'reminder', 'feedback_request',
    'waitlist_promoted', 'application_result', 'booking_result', 'personal_message'
);

CREATE TYPE notification_source AS ENUM ('scheduler', 'broadcast', 'admin_reply', 'system');

CREATE TYPE notification_status AS ENUM ('pending', 'sent', 'delivered', 'failed');

CREATE TYPE audit_action AS ENUM ('create', 'update', 'delete', 'restore', 'login', 'logout');

CREATE TYPE backup_type AS ENUM ('manual', 'daily', 'weekly');

CREATE TYPE backup_schedule AS ENUM ('daily', 'weekly', 'disabled');

CREATE TYPE operation_status AS ENUM ('pending', 'in_progress', 'completed', 'failed');

CREATE TYPE day_of_week AS ENUM ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday');

CREATE TYPE content_block_type AS ENUM ('text', 'html', 'json', 'image');

CREATE TYPE setting_value_type AS ENUM ('text', 'url', 'phone', 'email');

CREATE TYPE contact_source AS ENUM ('site_contacts', 'site_booking');

CREATE TYPE export_format AS ENUM ('google_sheets', 'csv');

-- ============================================================
-- 3. ФУНКЦІЯ АВТООНОВЛЕННЯ updated_at
-- ============================================================
CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- 4. ТАБЛИЦІ
-- ============================================================

-- ************************************************************
-- 4.1  РІВНІ КОРИСТУВАЧІВ
-- ************************************************************
CREATE TABLE user_levels (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(100) NOT NULL UNIQUE,
    slug            VARCHAR(100) NOT NULL UNIQUE,
    min_visits      INT NOT NULL DEFAULT 0,
    max_visits      INT,                          -- NULL = без верхнього ліміту
    sort_order      INT NOT NULL DEFAULT 0,
    description     TEXT,
    badge_icon      VARCHAR(255),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_user_levels_visits CHECK (
        min_visits >= 0
        AND (max_visits IS NULL OR max_visits >= min_visits)
    )
);

CREATE TRIGGER trg_user_levels_updated_at
    BEFORE UPDATE ON user_levels
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE user_levels IS 'Рівні відвідувачів: фоловер (0-4), середнячок (5-9), продвинутий (10+)';


-- ************************************************************
-- 4.2  РОЛІ АДМІНІСТРАТОРІВ
-- ************************************************************
CREATE TABLE admin_roles (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(50) NOT NULL UNIQUE,
    display_name    VARCHAR(100) NOT NULL,
    description     TEXT,
    permissions     JSONB NOT NULL DEFAULT '[]'::JSONB,
    access_level    INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_admin_roles_access_level CHECK (access_level BETWEEN 1 AND 4)
);

COMMENT ON TABLE admin_roles IS 'Ролі платформи: super_admin(1), admin(2), moderator(3), observer(4)';


-- ************************************************************
-- 4.3  АДМІНІСТРАТОРИ ПЛАТФОРМИ
-- ************************************************************
CREATE TABLE admin_users (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email               VARCHAR(255) NOT NULL UNIQUE,
    google_id           VARCHAR(255) UNIQUE,
    first_name          VARCHAR(100) NOT NULL,
    last_name           VARCHAR(100) NOT NULL,
    avatar_url          VARCHAR(500),
    role_id             UUID NOT NULL REFERENCES admin_roles(id) ON DELETE RESTRICT,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at       TIMESTAMPTZ,
    last_activity_at    TIMESTAMPTZ,
    invited_at          TIMESTAMPTZ,
    invited_by          UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_admin_users_role ON admin_users(role_id);
CREATE INDEX idx_admin_users_email ON admin_users(email);
CREATE INDEX idx_admin_users_active ON admin_users(is_active) WHERE is_active = TRUE;

CREATE TRIGGER trg_admin_users_updated_at
    BEFORE UPDATE ON admin_users
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE admin_users IS 'Адміністратори платформи (авторизація через Google OAuth 2.0)';


-- ************************************************************
-- 4.4  ЗАПРОШЕННЯ АДМІНІСТРАТОРІВ
-- ************************************************************
CREATE TABLE admin_invitations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email           VARCHAR(255) NOT NULL,
    role_id         UUID NOT NULL REFERENCES admin_roles(id) ON DELETE RESTRICT,
    invited_by      UUID NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
    token           VARCHAR(255) NOT NULL UNIQUE,
    status          invitation_status NOT NULL DEFAULT 'pending',
    expires_at      TIMESTAMPTZ NOT NULL,
    accepted_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_admin_invitations_email ON admin_invitations(email);
CREATE INDEX idx_admin_invitations_status ON admin_invitations(status);
CREATE INDEX idx_admin_invitations_token ON admin_invitations(token);

COMMENT ON TABLE admin_invitations IS 'Запрошення нових членів команди на платформу';


-- ************************************************************
-- 4.5  СЕСІЇ АДМІНІСТРАТОРІВ
-- ************************************************************
CREATE TABLE admin_sessions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    admin_user_id   UUID NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
    session_token   VARCHAR(500) NOT NULL UNIQUE,
    ip_address      VARCHAR(45),
    user_agent      TEXT,
    expires_at      TIMESTAMPTZ NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_active_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_admin_sessions_user ON admin_sessions(admin_user_id);
CREATE INDEX idx_admin_sessions_token ON admin_sessions(session_token);
CREATE INDEX idx_admin_sessions_active ON admin_sessions(is_active, expires_at)
    WHERE is_active = TRUE;

COMMENT ON TABLE admin_sessions IS 'Активні сесії адмінів (тайм-аут 8 годин неактивності)';


-- ************************************************************
-- 4.6  ФАЙЛИ ТА МЕДІА
-- ************************************************************
CREATE TABLE files (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    original_name   VARCHAR(500) NOT NULL,
    stored_name     VARCHAR(500) NOT NULL,
    mime_type       VARCHAR(100) NOT NULL,
    file_path       VARCHAR(1000) NOT NULL,
    thumbnail_path  VARCHAR(1000),
    file_size       BIGINT NOT NULL DEFAULT 0,
    width           INT,
    height          INT,
    alt_text        VARCHAR(500),
    entity_type     VARCHAR(100),
    entity_id       UUID,
    uploaded_by     UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_files_size CHECK (file_size >= 0)
);

CREATE INDEX idx_files_entity ON files(entity_type, entity_id);
CREATE INDEX idx_files_mime ON files(mime_type);
CREATE INDEX idx_files_uploaded_by ON files(uploaded_by);

COMMENT ON TABLE files IS 'Централізоване сховище файлів (зображення, документи)';


-- ************************************************************
-- 4.7  КОРИСТУВАЧІ БОТА (ВІДВІДУВАЧІ)
-- ************************************************************
CREATE TABLE users (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    telegram_id         BIGINT NOT NULL UNIQUE,
    telegram_username   VARCHAR(255),
    first_name          VARCHAR(100),
    last_name           VARCHAR(100),
    birth_date          DATE,
    phone               VARCHAR(20),
    level_id            UUID REFERENCES user_levels(id) ON DELETE SET NULL,
    visit_count         INT NOT NULL DEFAULT 0,
    is_profile_complete BOOLEAN NOT NULL DEFAULT FALSE,
    is_blocked          BOOLEAN NOT NULL DEFAULT FALSE,
    blocked_reason      VARCHAR(500),
    blocked_by          UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    blocked_at          TIMESTAMPTZ,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    last_activity_at    TIMESTAMPTZ,
    bot_started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    registered_at       TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_users_visit_count CHECK (visit_count >= 0)
);

CREATE INDEX idx_users_telegram_id ON users(telegram_id);
CREATE INDEX idx_users_level ON users(level_id);
CREATE INDEX idx_users_active ON users(is_active);
CREATE INDEX idx_users_blocked ON users(is_blocked) WHERE is_blocked = TRUE;
CREATE INDEX idx_users_phone ON users(phone) WHERE phone IS NOT NULL;
CREATE INDEX idx_users_name ON users USING gin (
    (COALESCE(first_name, '') || ' ' || COALESCE(last_name, '')) gin_trgm_ops
);
CREATE INDEX idx_users_profile_complete ON users(is_profile_complete)
    WHERE is_profile_complete = FALSE;
CREATE INDEX idx_users_last_activity ON users(last_activity_at);

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE users IS 'Відвідувачі, зареєстровані через Telegram-бот';


-- ************************************************************
-- 4.8  ПРОСТОРИ
-- ************************************************************
CREATE TABLE spaces (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name                VARCHAR(200) NOT NULL UNIQUE,
    slug                VARCHAR(200) NOT NULL UNIQUE,
    description         TEXT,
    short_description   TEXT,
    address             VARCHAR(500),
    cover_image_id      UUID REFERENCES files(id) ON DELETE SET NULL,
    schedule            JSONB DEFAULT '{}'::JSONB,
    has_coworking       BOOLEAN NOT NULL DEFAULT FALSE,
    has_studio          BOOLEAN NOT NULL DEFAULT FALSE,
    studio_name         VARCHAR(200),
    studio_description  TEXT,
    sort_order          INT NOT NULL DEFAULT 0,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_spaces_updated_at
    BEFORE UPDATE ON spaces
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE spaces IS 'Молодіжні простори: «Другий поверх», «Space Space»';


-- ************************************************************
-- 4.9  ФОТО ПРОСТОРІВ
-- ************************************************************
CREATE TABLE space_photos (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    space_id    UUID NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
    file_id     UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    sort_order  INT NOT NULL DEFAULT 0,
    caption     VARCHAR(500),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_space_photos_space ON space_photos(space_id);

COMMENT ON TABLE space_photos IS 'Фотогалерея просторів';


-- ************************************************************
-- 4.10 ЩОТИЖНЕВІ ФОРМАТИ ПРОСТОРІВ
-- ************************************************************
CREATE TABLE space_weekly_formats (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    space_id        UUID NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
    name            VARCHAR(200) NOT NULL,
    description     TEXT,
    day_of_week     day_of_week NOT NULL,
    start_time      TIME,
    end_time        TIME,
    cover_image_id  UUID REFERENCES files(id) ON DELETE SET NULL,
    sort_order      INT NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_space_weekly_formats_space ON space_weekly_formats(space_id);
CREATE INDEX idx_space_weekly_formats_day ON space_weekly_formats(day_of_week);

CREATE TRIGGER trg_space_weekly_formats_updated_at
    BEFORE UPDATE ON space_weekly_formats
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE space_weekly_formats IS 'Щотижневі формати подій у просторах';


-- ************************************************************
-- 4.11 ТИПИ ЗАХОДІВ
-- ************************************************************
CREATE TABLE event_types (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        VARCHAR(100) NOT NULL UNIQUE,
    slug        VARCHAR(100) NOT NULL UNIQUE,
    color       VARCHAR(7),
    icon        VARCHAR(100),
    sort_order  INT NOT NULL DEFAULT 0,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_event_types_updated_at
    BEFORE UPDATE ON event_types
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE event_types IS 'Довідник типів заходів: лекція, воркшоп, нетворкінг тощо';


-- ************************************************************
-- 4.12 ЗАХОДИ
-- ************************************************************
CREATE TABLE events (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title               VARCHAR(300) NOT NULL,
    short_description   TEXT NOT NULL,
    full_description    TEXT,
    event_type_id       UUID NOT NULL REFERENCES event_types(id) ON DELETE RESTRICT,
    starts_at           TIMESTAMPTZ NOT NULL,
    ends_at             TIMESTAMPTZ NOT NULL,
    space_id            UUID REFERENCES spaces(id) ON DELETE SET NULL,
    custom_location     VARCHAR(500),
    participant_limit   INT NOT NULL DEFAULT 0,
    waitlist_enabled    BOOLEAN NOT NULL DEFAULT FALSE,
    status              event_status NOT NULL DEFAULT 'draft',
    cover_image_id      UUID REFERENCES files(id) ON DELETE SET NULL,
    is_published        BOOLEAN NOT NULL DEFAULT FALSE,
    published_at        TIMESTAMPTZ,
    created_by          UUID NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
    updated_by          UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at          TIMESTAMPTZ,
    deleted_by          UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_events_dates CHECK (ends_at > starts_at),
    CONSTRAINT chk_events_limit CHECK (participant_limit >= 0),
    CONSTRAINT chk_events_waitlist CHECK (
        (waitlist_enabled = FALSE) OR (participant_limit > 0)
    )
);

CREATE INDEX idx_events_type ON events(event_type_id);
CREATE INDEX idx_events_space ON events(space_id);
CREATE INDEX idx_events_status ON events(status);
CREATE INDEX idx_events_starts ON events(starts_at);
CREATE INDEX idx_events_published ON events(is_published, status);
CREATE INDEX idx_events_created_by ON events(created_by);
CREATE INDEX idx_events_deleted ON events(is_deleted) WHERE is_deleted = FALSE;
CREATE INDEX idx_events_upcoming ON events(starts_at)
    WHERE status = 'published' AND is_deleted = FALSE;

CREATE TRIGGER trg_events_updated_at
    BEFORE UPDATE ON events
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE events IS 'Заходи ГО — центральна сутність системи';


-- ************************************************************
-- 4.13 РЕЄСТРАЦІЇ НА ЗАХОДИ
-- ************************************************************
CREATE TABLE event_registrations (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id                    UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id                     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status                      registration_status NOT NULL DEFAULT 'registered',
    is_anonymous                BOOLEAN NOT NULL DEFAULT FALSE,
    waitlist_position           INT,
    registration_source         registration_source NOT NULL DEFAULT 'bot',
    registered_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    confirmed_at                TIMESTAMPTZ,
    cancelled_at                TIMESTAMPTZ,
    promoted_from_waitlist_at   TIMESTAMPTZ,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_event_registrations_event_user UNIQUE (event_id, user_id),
    CONSTRAINT chk_registration_waitlist CHECK (
        (waitlist_position IS NULL) OR (waitlist_position > 0)
    )
);

CREATE INDEX idx_event_reg_event ON event_registrations(event_id);
CREATE INDEX idx_event_reg_user ON event_registrations(user_id);
CREATE INDEX idx_event_reg_status ON event_registrations(status);
CREATE INDEX idx_event_reg_event_status ON event_registrations(event_id, status);
CREATE INDEX idx_event_reg_waitlist ON event_registrations(event_id, waitlist_position)
    WHERE status = 'waitlisted';

CREATE TRIGGER trg_event_registrations_updated_at
    BEFORE UPDATE ON event_registrations
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE event_registrations IS 'Реєстрації відвідувачів на заходи (з підтримкою черги очікування)';


-- ************************************************************
-- 4.14 ВІДВІДУВАНІСТЬ ЗАХОДІВ
-- ************************************************************
CREATE TABLE event_attendance (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id        UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    registration_id UUID REFERENCES event_registrations(id) ON DELETE SET NULL,
    attended        BOOLEAN NOT NULL DEFAULT FALSE,
    marked_by       UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    marked_at       TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_event_attendance_event_user UNIQUE (event_id, user_id)
);

CREATE INDEX idx_event_att_event ON event_attendance(event_id);
CREATE INDEX idx_event_att_user ON event_attendance(user_id);
CREATE INDEX idx_event_att_attended ON event_attendance(event_id, attended)
    WHERE attended = TRUE;

COMMENT ON TABLE event_attendance IS 'Фактична присутність учасників (ручна відмітка адміном)';


-- ************************************************************
-- 4.15 ФОТО ЗАХОДІВ
-- ************************************************************
CREATE TABLE event_photos (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id    UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    file_id     UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    sort_order  INT NOT NULL DEFAULT 0,
    uploaded_by UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    is_deleted  BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_event_photos_event ON event_photos(event_id);
CREATE INDEX idx_event_photos_active ON event_photos(event_id)
    WHERE is_deleted = FALSE;

COMMENT ON TABLE event_photos IS 'Фотографії з заходів (доступні учасникам через бот)';


-- ************************************************************
-- 4.16 ФІДБЕКИ
-- ************************************************************
CREATE TABLE feedbacks (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id    UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rating      INT NOT NULL,
    comment     TEXT,
    source      feedback_source NOT NULL DEFAULT 'bot',
    is_visible  BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_feedbacks_event_user UNIQUE (event_id, user_id),
    CONSTRAINT chk_feedbacks_rating CHECK (rating BETWEEN 1 AND 5)
);

CREATE INDEX idx_feedbacks_event ON feedbacks(event_id);
CREATE INDEX idx_feedbacks_user ON feedbacks(user_id);
CREATE INDEX idx_feedbacks_rating ON feedbacks(event_id, rating);
CREATE INDEX idx_feedbacks_visible ON feedbacks(event_id)
    WHERE is_visible = TRUE;

CREATE TRIGGER trg_feedbacks_updated_at
    BEFORE UPDATE ON feedbacks
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE feedbacks IS 'Відгуки учасників після заходів (оцінка 1-5 + коментар)';


-- ************************************************************
-- 4.17 ПОВІДОМЛЕННЯ ВІД КОРИСТУВАЧІВ
-- ************************************************************
CREATE TABLE messages (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message_text    TEXT NOT NULL,
    status          message_status NOT NULL DEFAULT 'new',
    viewed_by       UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    viewed_at       TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_messages_user ON messages(user_id);
CREATE INDEX idx_messages_status ON messages(status);
CREATE INDEX idx_messages_new ON messages(created_at DESC)
    WHERE status = 'new';

COMMENT ON TABLE messages IS 'Вхідні повідомлення від користувачів бота ("Написати команді")';


-- ************************************************************
-- 4.18 ВІДПОВІДІ НА ПОВІДОМЛЕННЯ
-- ************************************************************
CREATE TABLE message_replies (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id      UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    admin_user_id   UUID NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
    reply_text      TEXT NOT NULL,
    is_sent         BOOLEAN NOT NULL DEFAULT FALSE,
    sent_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_message_replies_message ON message_replies(message_id);
CREATE INDEX idx_message_replies_admin ON message_replies(admin_user_id);
CREATE INDEX idx_message_replies_unsent ON message_replies(is_sent)
    WHERE is_sent = FALSE;

COMMENT ON TABLE message_replies IS 'Відповіді адмінів користувачам (надсилаються в Telegram)';


-- ************************************************************
-- 4.19 РОЗСИЛКИ
-- ************************************************************
CREATE TABLE broadcasts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title               VARCHAR(300) NOT NULL,
    message_text        TEXT NOT NULL,
    image_id            UUID REFERENCES files(id) ON DELETE SET NULL,
    audience_type       broadcast_audience NOT NULL DEFAULT 'all',
    audience_event_id   UUID REFERENCES events(id) ON DELETE SET NULL,
    audience_level_id   UUID REFERENCES user_levels(id) ON DELETE SET NULL,
    status              broadcast_status NOT NULL DEFAULT 'draft',
    scheduled_at        TIMESTAMPTZ,
    sent_at             TIMESTAMPTZ,
    total_recipients    INT NOT NULL DEFAULT 0,
    delivered_count     INT NOT NULL DEFAULT 0,
    failed_count        INT NOT NULL DEFAULT 0,
    created_by          UUID NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_broadcasts_counts CHECK (
        total_recipients >= 0 AND delivered_count >= 0 AND failed_count >= 0
    ),
    CONSTRAINT chk_broadcasts_audience_event CHECK (
        audience_type != 'event' OR audience_event_id IS NOT NULL
    ),
    CONSTRAINT chk_broadcasts_audience_level CHECK (
        audience_type != 'level' OR audience_level_id IS NOT NULL
    )
);

CREATE INDEX idx_broadcasts_status ON broadcasts(status);
CREATE INDEX idx_broadcasts_scheduled ON broadcasts(scheduled_at)
    WHERE status = 'scheduled';
CREATE INDEX idx_broadcasts_created_by ON broadcasts(created_by);

CREATE TRIGGER trg_broadcasts_updated_at
    BEFORE UPDATE ON broadcasts
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE broadcasts IS 'Розсилки: всім / по заходу / по рівню';


-- ************************************************************
-- 4.20 ОТРИМУВАЧІ РОЗСИЛОК
-- ************************************************************
CREATE TABLE broadcast_recipients (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    broadcast_id    UUID NOT NULL REFERENCES broadcasts(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    delivery_status delivery_status NOT NULL DEFAULT 'pending',
    error_message   TEXT,
    delivered_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_broadcast_recipient UNIQUE (broadcast_id, user_id)
);

CREATE INDEX idx_broadcast_recip_broadcast ON broadcast_recipients(broadcast_id);
CREATE INDEX idx_broadcast_recip_user ON broadcast_recipients(user_id);
CREATE INDEX idx_broadcast_recip_status ON broadcast_recipients(broadcast_id, delivery_status);

COMMENT ON TABLE broadcast_recipients IS 'Логування доставки розсилки кожному отримувачу';


-- ************************************************************
-- 4.21 ШАБЛОНИ ШЕДУЛЕРІВ
-- ************************************************************
CREATE TABLE scheduler_templates (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slug                VARCHAR(100) NOT NULL UNIQUE,
    name                VARCHAR(200) NOT NULL,
    description         TEXT,
    message_template    TEXT NOT NULL,
    trigger_type        scheduler_trigger NOT NULL,
    cron_expression     VARCHAR(100),
    offset_minutes      INT,
    audience_type       scheduler_audience NOT NULL DEFAULT 'all',
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    updated_by          UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_scheduler_templates_updated_at
    BEFORE UPDATE ON scheduler_templates
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE scheduler_templates IS 'Шаблони автоматичних повідомлень бота (5 шедулерів)';


-- ************************************************************
-- 4.22 ЛОГИ ШЕДУЛЕРІВ
-- ************************************************************
CREATE TABLE scheduler_logs (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    template_id      UUID NOT NULL REFERENCES scheduler_templates(id) ON DELETE CASCADE,
    event_id         UUID REFERENCES events(id) ON DELETE SET NULL,
    status           scheduler_run_status NOT NULL DEFAULT 'triggered',
    recipients_count INT NOT NULL DEFAULT 0,
    delivered_count  INT NOT NULL DEFAULT 0,
    error_details    TEXT,
    triggered_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at     TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_scheduler_logs_template ON scheduler_logs(template_id);
CREATE INDEX idx_scheduler_logs_event ON scheduler_logs(event_id);
CREATE INDEX idx_scheduler_logs_triggered ON scheduler_logs(triggered_at DESC);

COMMENT ON TABLE scheduler_logs IS 'Журнал виконання автоматичних розсилок';


-- ************************************************************
-- 4.23 ЗАЯВКИ НА ВСТУП В КОМАНДУ
-- ************************************************************
CREATE TABLE team_join_applications (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id           UUID REFERENCES users(id) ON DELETE SET NULL,
    applicant_name    VARCHAR(200),
    applicant_contact VARCHAR(200),
    status            application_status NOT NULL DEFAULT 'new',
    admin_notes       TEXT,
    reviewed_by       UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    reviewed_at       TIMESTAMPTZ,
    source            VARCHAR(50) NOT NULL DEFAULT 'bot',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_team_join_status ON team_join_applications(status);
CREATE INDEX idx_team_join_user ON team_join_applications(user_id);
CREATE INDEX idx_team_join_new ON team_join_applications(created_at DESC)
    WHERE status = 'new';

CREATE TRIGGER trg_team_join_applications_updated_at
    BEFORE UPDATE ON team_join_applications
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE team_join_applications IS 'Заявки на вступ до команди ГО';


-- ************************************************************
-- 4.24 ПИТАННЯ АНКЕТИ
-- ************************************************************
CREATE TABLE application_questions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    question_text   TEXT NOT NULL,
    question_type   question_type NOT NULL DEFAULT 'text',
    options         JSONB,
    sort_order      INT NOT NULL DEFAULT 0,
    is_required     BOOLEAN NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_application_questions_updated_at
    BEFORE UPDATE ON application_questions
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE application_questions IS 'Питання анкети для заявки на вступ в команду';


-- ************************************************************
-- 4.25 ВІДПОВІДІ НА АНКЕТУ
-- ************************************************************
CREATE TABLE application_answers (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    application_id  UUID NOT NULL REFERENCES team_join_applications(id) ON DELETE CASCADE,
    question_id     UUID NOT NULL REFERENCES application_questions(id) ON DELETE CASCADE,
    answer_text     TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_application_answer UNIQUE (application_id, question_id)
);

CREATE INDEX idx_app_answers_application ON application_answers(application_id);

COMMENT ON TABLE application_answers IS 'Відповіді заявників на питання анкети';


-- ************************************************************
-- 4.26 ЗАЯВКИ НА БРОНЮВАННЯ ПРОСТОРУ
-- ************************************************************
CREATE TABLE space_booking_requests (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_name          VARCHAR(300) NOT NULL,
    event_description   TEXT,
    space_id            UUID NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
    booking_date        DATE NOT NULL,
    start_time          TIME NOT NULL,
    end_time            TIME NOT NULL,
    contact_name        VARCHAR(200) NOT NULL,
    contact_phone       VARCHAR(20),
    contact_email       VARCHAR(255),
    user_id             UUID REFERENCES users(id) ON DELETE SET NULL,
    status              booking_status NOT NULL DEFAULT 'new',
    admin_notes         TEXT,
    reviewed_by         UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    reviewed_at         TIMESTAMPTZ,
    source              VARCHAR(20) NOT NULL DEFAULT 'site',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_booking_time CHECK (end_time > start_time)
);

CREATE INDEX idx_booking_space ON space_booking_requests(space_id);
CREATE INDEX idx_booking_date ON space_booking_requests(booking_date);
CREATE INDEX idx_booking_status ON space_booking_requests(status);
CREATE INDEX idx_booking_space_date ON space_booking_requests(space_id, booking_date);
CREATE INDEX idx_booking_new ON space_booking_requests(created_at DESC)
    WHERE status = 'new';

CREATE TRIGGER trg_space_booking_requests_updated_at
    BEFORE UPDATE ON space_booking_requests
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE space_booking_requests IS 'Заявки на бронювання просторів (з календарем зайнятості)';


-- ************************************************************
-- 4.27 СТОРІНКИ САЙТУ
-- ************************************************************
CREATE TABLE site_pages (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slug                VARCHAR(200) NOT NULL UNIQUE,
    title               VARCHAR(300) NOT NULL,
    meta_description    TEXT,
    meta_keywords       VARCHAR(500),
    is_published        BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order          INT NOT NULL DEFAULT 0,
    parent_page_id      UUID REFERENCES site_pages(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_site_pages_slug ON site_pages(slug);
CREATE INDEX idx_site_pages_parent ON site_pages(parent_page_id);
CREATE INDEX idx_site_pages_published ON site_pages(is_published)
    WHERE is_published = TRUE;

CREATE TRIGGER trg_site_pages_updated_at
    BEFORE UPDATE ON site_pages
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE site_pages IS 'Ієрархічна структура сторінок публічного сайту';


-- ************************************************************
-- 4.28 БЛОКИ КОНТЕНТУ СТОРІНОК
-- ************************************************************
CREATE TABLE site_content_blocks (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    page_id     UUID NOT NULL REFERENCES site_pages(id) ON DELETE CASCADE,
    block_key   VARCHAR(100) NOT NULL,
    block_type  content_block_type NOT NULL DEFAULT 'text',
    content     TEXT,
    metadata    JSONB DEFAULT '{}'::JSONB,
    sort_order  INT NOT NULL DEFAULT 0,
    updated_by  UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_content_block_key UNIQUE (page_id, block_key)
);

CREATE INDEX idx_content_blocks_page ON site_content_blocks(page_id);

CREATE TRIGGER trg_site_content_blocks_updated_at
    BEFORE UPDATE ON site_content_blocks
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE site_content_blocks IS 'Блоки контенту: місія, візія, цінності, інтро, лічильники';


-- ************************************************************
-- 4.29 ЛІЧИЛЬНИКИ САЙТУ
-- ************************************************************
CREATE TABLE site_counters (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    label       VARCHAR(200) NOT NULL,
    icon        VARCHAR(100),
    value       INT NOT NULL DEFAULT 0,
    suffix      VARCHAR(50),
    is_auto     BOOLEAN NOT NULL DEFAULT FALSE,
    auto_source VARCHAR(100),
    sort_order  INT NOT NULL DEFAULT 0,
    is_visible  BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE site_counters IS 'Кількісні показники на головній сторінці';


-- ************************************************************
-- 4.30 КАТЕГОРІЇ ПУБЛІКАЦІЙ
-- ************************************************************
CREATE TABLE publication_categories (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        VARCHAR(100) NOT NULL UNIQUE,
    slug        VARCHAR(100) NOT NULL UNIQUE,
    color       VARCHAR(7),
    sort_order  INT NOT NULL DEFAULT 0,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE publication_categories IS 'Категорії новин: анонс, подія, навчання тощо';


-- ************************************************************
-- 4.31 ПУБЛІКАЦІЇ / НОВИНИ
-- ************************************************************
CREATE TABLE publications (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title           VARCHAR(300) NOT NULL,
    excerpt         TEXT,
    content         TEXT NOT NULL,
    cover_image_id  UUID REFERENCES files(id) ON DELETE SET NULL,
    category_id     UUID NOT NULL REFERENCES publication_categories(id) ON DELETE RESTRICT,
    status          publication_status NOT NULL DEFAULT 'draft',
    published_at    TIMESTAMPTZ,
    scheduled_at    TIMESTAMPTZ,
    slug            VARCHAR(300) NOT NULL UNIQUE,
    created_by      UUID NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
    updated_by      UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ,
    deleted_by      UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_publications_category ON publications(category_id);
CREATE INDEX idx_publications_status ON publications(status);
CREATE INDEX idx_publications_slug ON publications(slug);
CREATE INDEX idx_publications_published ON publications(published_at DESC)
    WHERE status = 'published' AND is_deleted = FALSE;
CREATE INDEX idx_publications_scheduled ON publications(scheduled_at)
    WHERE status = 'scheduled' AND is_deleted = FALSE;
CREATE INDEX idx_publications_created_by ON publications(created_by);

CREATE TRIGGER trg_publications_updated_at
    BEFORE UPDATE ON publications
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE publications IS 'Новини та публікації сайту (з запланованою публікацією)';


-- ************************************************************
-- 4.32 ФОТО ПУБЛІКАЦІЙ
-- ************************************************************
CREATE TABLE publication_photos (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    publication_id  UUID NOT NULL REFERENCES publications(id) ON DELETE CASCADE,
    file_id         UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    sort_order      INT NOT NULL DEFAULT 0,
    caption         VARCHAR(500),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_publication_photos_pub ON publication_photos(publication_id);

COMMENT ON TABLE publication_photos IS 'Додаткові фото до публікацій';


-- ************************************************************
-- 4.33 ПРОЄКТИ
-- ************************************************************
CREATE TABLE projects (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title               VARCHAR(300) NOT NULL,
    short_description   TEXT,
    full_description    TEXT,
    cover_image_id      UUID REFERENCES files(id) ON DELETE SET NULL,
    status              project_status NOT NULL DEFAULT 'active',
    start_date          DATE,
    end_date            DATE,
    slug                VARCHAR(300) NOT NULL UNIQUE,
    sort_order          INT NOT NULL DEFAULT 0,
    created_by          UUID NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at          TIMESTAMPTZ,
    deleted_by          UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_projects_dates CHECK (
        end_date IS NULL OR start_date IS NULL OR end_date >= start_date
    )
);

CREATE INDEX idx_projects_status ON projects(status);
CREATE INDEX idx_projects_slug ON projects(slug);
CREATE INDEX idx_projects_active ON projects(sort_order)
    WHERE status = 'active' AND is_deleted = FALSE;

CREATE TRIGGER trg_projects_updated_at
    BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE projects IS 'Проєкти ГО (активні та завершені)';


-- ************************************************************
-- 4.34 ФОТО ПРОЄКТІВ
-- ************************************************************
CREATE TABLE project_photos (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id  UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    file_id     UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    sort_order  INT NOT NULL DEFAULT 0,
    caption     VARCHAR(500),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_project_photos_project ON project_photos(project_id);

COMMENT ON TABLE project_photos IS 'Фотогалерея проєктів';


-- ************************************************************
-- 4.35 ЧЛЕНИ КОМАНДИ (САЙТ)
-- ************************************************************
CREATE TABLE team_members (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    first_name      VARCHAR(100) NOT NULL,
    last_name       VARCHAR(100) NOT NULL,
    role_title      VARCHAR(200),
    bio             TEXT,
    photo_id        UUID REFERENCES files(id) ON DELETE SET NULL,
    instagram_url   VARCHAR(500),
    telegram_url    VARCHAR(500),
    sort_order      INT NOT NULL DEFAULT 0,
    is_visible      BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ,
    deleted_by      UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_team_members_visible ON team_members(sort_order)
    WHERE is_visible = TRUE AND is_deleted = FALSE;

CREATE TRIGGER trg_team_members_updated_at
    BEFORE UPDATE ON team_members
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE team_members IS 'Картки членів команди для публічного сайту';


-- ************************************************************
-- 4.36 ПАРТНЕРИ
-- ************************************************************
CREATE TABLE partners (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        VARCHAR(300) NOT NULL,
    logo_id     UUID REFERENCES files(id) ON DELETE SET NULL,
    website_url VARCHAR(500),
    description TEXT,
    sort_order  INT NOT NULL DEFAULT 0,
    is_visible  BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted  BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at  TIMESTAMPTZ,
    deleted_by  UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_partners_visible ON partners(sort_order)
    WHERE is_visible = TRUE AND is_deleted = FALSE;

CREATE TRIGGER trg_partners_updated_at
    BEFORE UPDATE ON partners
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE partners IS 'Партнери ГО (логотип, назва, посилання)';


-- ************************************************************
-- 4.37 БІБЛІОТЕКА
-- ************************************************************
CREATE TABLE library_items (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title               VARCHAR(300) NOT NULL,
    item_type           library_item_type NOT NULL,
    author              VARCHAR(200),
    genre               VARCHAR(200),
    description         TEXT,
    cover_image_id      UUID REFERENCES files(id) ON DELETE SET NULL,
    availability_status availability_status NOT NULL DEFAULT 'available',
    borrowed_by         VARCHAR(200),
    borrowed_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    borrowed_at         DATE,
    expected_return_date DATE,
    space_id            UUID REFERENCES spaces(id) ON DELETE SET NULL,
    sort_order          INT NOT NULL DEFAULT 0,
    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at          TIMESTAMPTZ,
    deleted_by          UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_library_type ON library_items(item_type);
CREATE INDEX idx_library_availability ON library_items(availability_status);
CREATE INDEX idx_library_space ON library_items(space_id);
CREATE INDEX idx_library_active ON library_items(item_type, sort_order)
    WHERE is_deleted = FALSE;

CREATE TRIGGER trg_library_items_updated_at
    BEFORE UPDATE ON library_items
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE library_items IS 'Бібліотека: книги, настільні ігри, PS5';


-- ************************************************************
-- 4.38 ІСТОРІЯ ВИДАЧ БІБЛІОТЕКИ
-- ************************************************************
CREATE TABLE library_borrow_history (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    item_id         UUID NOT NULL REFERENCES library_items(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES users(id) ON DELETE SET NULL,
    borrower_name   VARCHAR(200),
    borrowed_at     DATE NOT NULL DEFAULT CURRENT_DATE,
    returned_at     DATE,
    notes           TEXT,
    issued_by       UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_borrow_history_item ON library_borrow_history(item_id);
CREATE INDEX idx_borrow_history_user ON library_borrow_history(user_id);
CREATE INDEX idx_borrow_history_active ON library_borrow_history(item_id)
    WHERE returned_at IS NULL;

COMMENT ON TABLE library_borrow_history IS 'Журнал видач та повернень';


-- ************************************************************
-- 4.39 НОТИФІКАЦІЇ БОТА
-- ************************************************************
CREATE TABLE bot_notifications (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    notification_type   notification_type NOT NULL,
    source_type         notification_source NOT NULL DEFAULT 'system',
    source_id           UUID,
    message_text        TEXT NOT NULL,
    status              notification_status NOT NULL DEFAULT 'pending',
    error_message       TEXT,
    retry_count         INT NOT NULL DEFAULT 0,
    scheduled_at        TIMESTAMPTZ,
    sent_at             TIMESTAMPTZ,
    delivered_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_notification_retry CHECK (retry_count >= 0)
);

CREATE INDEX idx_bot_notif_user ON bot_notifications(user_id);
CREATE INDEX idx_bot_notif_status ON bot_notifications(status);
CREATE INDEX idx_bot_notif_type ON bot_notifications(notification_type);
CREATE INDEX idx_bot_notif_pending ON bot_notifications(scheduled_at)
    WHERE status = 'pending';
CREATE INDEX idx_bot_notif_source ON bot_notifications(source_type, source_id);

COMMENT ON TABLE bot_notifications IS 'Журнал усіх сповіщень Telegram-бота';


-- ************************************************************
-- 4.40 КОНТАКТНІ ФОРМИ САЙТУ
-- ************************************************************
CREATE TABLE contact_form_submissions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sender_name     VARCHAR(200) NOT NULL,
    sender_email    VARCHAR(255),
    sender_phone    VARCHAR(20),
    message_text    TEXT NOT NULL,
    status          message_status NOT NULL DEFAULT 'new',
    viewed_by       UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    viewed_at       TIMESTAMPTZ,
    source          contact_source NOT NULL DEFAULT 'site_contacts',
    ip_address      VARCHAR(45),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_contact_forms_status ON contact_form_submissions(status);
CREATE INDEX idx_contact_forms_new ON contact_form_submissions(created_at DESC)
    WHERE status = 'new';

COMMENT ON TABLE contact_form_submissions IS 'Звернення з контактних форм сайту';


-- ************************************************************
-- 4.41 ЖУРНАЛ ДІЙ (АУДИТ)
-- ************************************************************
CREATE TABLE audit_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    admin_user_id   UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    action          audit_action NOT NULL,
    entity_type     VARCHAR(100) NOT NULL,
    entity_id       UUID,
    entity_name     VARCHAR(300),
    old_values      JSONB,
    new_values      JSONB,
    ip_address      VARCHAR(45),
    user_agent      TEXT,
    description     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_admin ON audit_logs(admin_user_id);
CREATE INDEX idx_audit_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_audit_action ON audit_logs(action);
CREATE INDEX idx_audit_date ON audit_logs(created_at DESC);
CREATE INDEX idx_audit_admin_date ON audit_logs(admin_user_id, created_at DESC);

COMMENT ON TABLE audit_logs IS 'Повний журнал дій адміністраторів (хто, що, коли)';


-- ************************************************************
-- 4.42 КОШИК (SOFT DELETE)
-- ************************************************************
CREATE TABLE trash_bin (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entity_type     VARCHAR(100) NOT NULL,
    entity_id       UUID NOT NULL,
    entity_name     VARCHAR(300),
    entity_snapshot JSONB NOT NULL,
    deleted_by      UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    deleted_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 days'),
    is_restored     BOOLEAN NOT NULL DEFAULT FALSE,
    restored_at     TIMESTAMPTZ,
    restored_by     UUID REFERENCES admin_users(id) ON DELETE SET NULL
);

CREATE INDEX idx_trash_entity ON trash_bin(entity_type, entity_id);
CREATE INDEX idx_trash_expires ON trash_bin(expires_at)
    WHERE is_restored = FALSE;
CREATE INDEX idx_trash_active ON trash_bin(entity_type, deleted_at DESC)
    WHERE is_restored = FALSE;

COMMENT ON TABLE trash_bin IS 'Кошик з відновленням протягом 30 днів';


-- ************************************************************
-- 4.43 НАЛАШТУВАННЯ ОРГАНІЗАЦІЇ
-- ************************************************************
CREATE TABLE organization_settings (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    key             VARCHAR(100) NOT NULL UNIQUE,
    value           TEXT,
    display_name    VARCHAR(200),
    group_name      VARCHAR(50) NOT NULL DEFAULT 'general',
    value_type      setting_value_type NOT NULL DEFAULT 'text',
    sort_order      INT NOT NULL DEFAULT 0,
    updated_by      UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_org_settings_updated_at
    BEFORE UPDATE ON organization_settings
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE organization_settings IS 'Глобальні налаштування ГО';


-- ************************************************************
-- 4.44 НАЛАШТУВАННЯ ІНТЕГРАЦІЙ
-- ************************************************************
CREATE TABLE integration_settings (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    provider        VARCHAR(100) NOT NULL UNIQUE,
    display_name    VARCHAR(200) NOT NULL,
    config          JSONB NOT NULL DEFAULT '{}'::JSONB,
    is_active       BOOLEAN NOT NULL DEFAULT FALSE,
    last_synced_at  TIMESTAMPTZ,
    sync_status     VARCHAR(20) NOT NULL DEFAULT 'never',
    last_error      TEXT,
    updated_by      UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_integration_settings_updated_at
    BEFORE UPDATE ON integration_settings
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE integration_settings IS 'Інтеграції: Google OAuth, Sheets, Forms, Telegram Bot';


-- ************************************************************
-- 4.45 ЗАПИСИ БЕКАПІВ
-- ************************************************************
CREATE TABLE backup_records (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    backup_type     backup_type NOT NULL,
    file_path       VARCHAR(1000),
    file_size       BIGINT,
    status          operation_status NOT NULL DEFAULT 'in_progress',
    error_message   TEXT,
    initiated_by    UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_backup_records_type ON backup_records(backup_type);
CREATE INDEX idx_backup_records_status ON backup_records(status);
CREATE INDEX idx_backup_records_date ON backup_records(started_at DESC);

COMMENT ON TABLE backup_records IS 'Журнал резервних копій БД';


-- ************************************************************
-- 4.46 НАЛАШТУВАННЯ БЕКАПІВ
-- ************************************************************
CREATE TABLE backup_settings (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    schedule_type   backup_schedule NOT NULL DEFAULT 'daily',
    backup_time     TIME NOT NULL DEFAULT '03:00',
    day_of_week     day_of_week,
    retention_days  INT NOT NULL DEFAULT 30,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    updated_by      UUID REFERENCES admin_users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_backup_retention CHECK (retention_days >= 1)
);

CREATE TRIGGER trg_backup_settings_updated_at
    BEFORE UPDATE ON backup_settings
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

COMMENT ON TABLE backup_settings IS 'Налаштування автоматичного резервного копіювання';


-- ************************************************************
-- 4.47 ЛОГИ ЕКСПОРТУ
-- ************************************************************
CREATE TABLE export_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    export_type     VARCHAR(100) NOT NULL,
    format          export_format NOT NULL DEFAULT 'google_sheets',
    destination_url VARCHAR(1000),
    records_count   INT NOT NULL DEFAULT 0,
    exported_by     UUID NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
    status          operation_status NOT NULL DEFAULT 'pending',
    error_message   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_export_logs_type ON export_logs(export_type);
CREATE INDEX idx_export_logs_by ON export_logs(exported_by);
CREATE INDEX idx_export_logs_date ON export_logs(created_at DESC);

COMMENT ON TABLE export_logs IS 'Журнал експортів в Google Sheets / CSV';


-- ============================================================
-- 5. ПОЧАТКОВІ ДАНІ (SEED DATA)
-- ============================================================

-- Ролі адміністраторів
INSERT INTO admin_roles (name, display_name, description, permissions, access_level) VALUES
    ('super_admin', 'Супер-адмін', 'Повний доступ включаючи управління ролями та налаштуваннями', '["*"]', 1),
    ('admin', 'Адмін', 'Все крім управління ролями інших адмінів', '["events","users","content","communication","applications","analytics","library"]', 2),
    ('moderator', 'Модератор', 'Контент сайту, комунікація, перегляд заявок', '["content","communication","applications.view"]', 3),
    ('observer', 'Спостерігач', 'Тільки перегляд без права редагування', '["*.view"]', 4);

-- Рівні користувачів
INSERT INTO user_levels (name, slug, min_visits, max_visits, sort_order, description) VALUES
    ('Фоловер', 'follower', 0, 4, 1, 'Початковий рівень — від 0 до 4 відвідувань'),
    ('Середнячок', 'intermediate', 5, 9, 2, 'Середній рівень — від 5 до 9 відвідувань'),
    ('Продвинутий', 'advanced', 10, NULL, 3, 'Максимальний рівень — 10+ відвідувань');

-- Типи заходів
INSERT INTO event_types (name, slug, color, sort_order) VALUES
    ('Лекція', 'lecture', '#534AB7', 1),
    ('Воркшоп', 'workshop', '#1D9E75', 2),
    ('Нетворкінг', 'networking', '#D85A30', 3),
    ('Кінопоказ', 'screening', '#378ADD', 4),
    ('Дискусія', 'discussion', '#D4537E', 5),
    ('Майстер-клас', 'masterclass', '#639922', 6),
    ('Вечірка', 'party', '#BA7517', 7),
    ('Інше', 'other', '#888780', 99);

-- Простори
INSERT INTO spaces (name, slug, short_description, has_coworking, has_studio, studio_name, sort_order) VALUES
    ('Другий поверх', 'drugyy-poverh', 'Молодіжний простір з коворкінгом та аудіовізуальною студією', TRUE, TRUE, 'Студія "КОНТЕНТА"', 1),
    ('Space Space', 'space-space', 'Молодіжний простір для подій та зустрічей', FALSE, FALSE, NULL, 2);

-- Категорії публікацій
INSERT INTO publication_categories (name, slug, color, sort_order) VALUES
    ('Анонс', 'announcement', '#534AB7', 1),
    ('Подія', 'event-recap', '#1D9E75', 2),
    ('Навчання команди', 'team-learning', '#378ADD', 3),
    ('Цікаві події', 'interesting', '#D85A30', 4);

-- Шаблони шедулерів
INSERT INTO scheduler_templates (slug, name, description, message_template, trigger_type, offset_minutes, audience_type) VALUES
    ('new_event', 'Новий захід', 'Сповіщення при публікації нового заходу',
     E'🎉 Новий захід!\n\n{{event_title}}\n📅 {{event_date}}\n⏰ {{event_time}}\n📍 {{event_location}}\n\n{{event_description}}\n\nЗареєструватися: /events',
     'event_publish', NULL, 'all'),
    ('weekly_digest', 'Тижневий дайджест', 'Щонеділі о 12:00 — анонс заходів тижня',
     E'📋 Заходи на цьому тижні:\n\n{{events_list}}\n\nДетальніше: /events',
     'cron', NULL, 'all'),
    ('pre_event_reminder', 'Нагадування перед заходом', 'За 2 години до початку',
     E'⏰ Нагадування!\n\nЧерез 2 години починається:\n{{event_title}}\n📍 {{event_location}}\n\nЧекаємо на тебе! 🤗',
     'time_before_event', -120, 'registered'),
    ('post_event_feedback', 'Фідбек після заходу', 'Через 2 години після завершення',
     E'💬 Дякуємо що був(ла) на {{event_title}}!\n\nЗалиш відгук:\n/feedback_{{event_id}}',
     'time_after_event', 120, 'registered'),
    ('incomplete_profile', 'Незаповнений профіль', 'Через 24 години після /start',
     E'👋 Привіт! Твій профіль ще не заповнений.\n\nЗаповни його для персональних нагадувань!\n\n/profile',
     'user_register', 1440, 'new_users');

-- Сторінки сайту
INSERT INTO site_pages (slug, title, sort_order) VALUES
    ('home', 'Головна', 1),
    ('about', 'Про нас', 2),
    ('what-we-do', 'Що ми робимо?', 3),
    ('team', 'Команда', 4),
    ('opportunities', 'Можливості', 5),
    ('news', 'Новини', 6),
    ('spaces', 'Напрями роботи', 7),
    ('projects', 'Проєкти', 8),
    ('partners', 'Партнери', 9),
    ('contacts', 'Контакти', 10);

-- Дочірні сторінки просторів
INSERT INTO site_pages (slug, title, sort_order, parent_page_id)
SELECT s.slug || '-space', 'Простір ' || s.name, s.sort_order,
       (SELECT id FROM site_pages WHERE slug = 'spaces')
FROM spaces s;

-- Бібліотечні підсторінки
INSERT INTO site_pages (slug, title, sort_order, parent_page_id) VALUES
    ('books', 'Буккросинг', 11, (SELECT id FROM site_pages WHERE slug = 'spaces')),
    ('games', 'Ігри', 12, (SELECT id FROM site_pages WHERE slug = 'spaces'));

-- Налаштування організації
INSERT INTO organization_settings (key, value, display_name, group_name, value_type, sort_order) VALUES
    ('org_name', 'ГО «Олександрійська молодь»', 'Назва організації', 'general', 'text', 1),
    ('org_phone', NULL, 'Контактний телефон', 'contacts', 'phone', 2),
    ('org_email', NULL, 'Email організації', 'contacts', 'email', 3),
    ('address_drugyy_poverh', NULL, 'Адреса "Другий поверх"', 'contacts', 'text', 4),
    ('address_space_space', NULL, 'Адреса "Space Space"', 'contacts', 'text', 5),
    ('instagram_url', NULL, 'Instagram', 'social', 'url', 6),
    ('telegram_url', NULL, 'Telegram', 'social', 'url', 7);

-- Налаштування інтеграцій
INSERT INTO integration_settings (provider, display_name, is_active) VALUES
    ('google_oauth', 'Google OAuth 2.0', FALSE),
    ('google_sheets', 'Google Sheets', FALSE),
    ('google_forms', 'Google Forms', FALSE),
    ('telegram_bot', 'Telegram Bot', FALSE);

-- Налаштування бекапу
INSERT INTO backup_settings (schedule_type, backup_time, retention_days, is_active) VALUES
    ('daily', '03:00', 30, TRUE);


-- ============================================================
-- 6. ПРЕДСТАВЛЕННЯ (VIEWS) ДЛЯ АНАЛІТИКИ
-- ============================================================

-- 6.1 Зведена статистика заходів
CREATE OR REPLACE VIEW v_event_statistics AS
SELECT
    e.id AS event_id,
    e.title,
    e.starts_at,
    e.status,
    et.name AS event_type,
    s.name AS space_name,
    e.participant_limit,
    COUNT(er.id) FILTER (WHERE er.status IN ('registered','confirmed')) AS registered_count,
    COUNT(er.id) FILTER (WHERE er.status = 'waitlisted') AS waitlisted_count,
    COUNT(er.id) FILTER (WHERE er.status = 'confirmed') AS confirmed_count,
    COUNT(ea.id) FILTER (WHERE ea.attended = TRUE) AS attended_count,
    ROUND(
        CASE WHEN COUNT(er.id) FILTER (WHERE er.status IN ('registered','confirmed')) = 0 THEN 0
        ELSE COUNT(ea.id) FILTER (WHERE ea.attended = TRUE)::NUMERIC
             / COUNT(er.id) FILTER (WHERE er.status IN ('registered','confirmed')) * 100
        END, 1
    ) AS attendance_rate_pct,
    COALESCE(AVG(f.rating), 0) AS avg_rating,
    COUNT(DISTINCT f.id) AS feedback_count
FROM events e
LEFT JOIN event_types et ON e.event_type_id = et.id
LEFT JOIN spaces s ON e.space_id = s.id
LEFT JOIN event_registrations er ON e.id = er.event_id
LEFT JOIN event_attendance ea ON e.id = ea.event_id
LEFT JOIN feedbacks f ON e.id = f.event_id AND f.is_visible = TRUE
WHERE e.is_deleted = FALSE
GROUP BY e.id, e.title, e.starts_at, e.status, et.name, s.name, e.participant_limit;

COMMENT ON VIEW v_event_statistics IS 'Зведена аналітика по кожному заходу';


-- 6.2 Розподіл користувачів по рівнях
CREATE OR REPLACE VIEW v_user_level_distribution AS
SELECT
    ul.name AS level_name,
    ul.slug,
    ul.sort_order,
    COUNT(u.id) AS users_count,
    COUNT(u.id) FILTER (WHERE u.is_profile_complete) AS with_complete_profile,
    COUNT(u.id) FILTER (WHERE u.last_activity_at >= NOW() - INTERVAL '30 days') AS active_30d,
    COUNT(u.id) FILTER (WHERE u.last_activity_at < NOW() - INTERVAL '60 days' OR u.last_activity_at IS NULL) AS inactive_60d
FROM user_levels ul
LEFT JOIN users u ON ul.id = u.level_id AND NOT u.is_blocked
GROUP BY ul.id, ul.name, ul.slug, ul.sort_order
ORDER BY ul.sort_order;

COMMENT ON VIEW v_user_level_distribution IS 'Розподіл по рівнях (для дашборда)';


-- 6.3 Дашборд: зведені лічильники
CREATE OR REPLACE VIEW v_dashboard_stats AS
SELECT
    (SELECT COUNT(*) FROM users WHERE NOT is_blocked) AS total_users,
    (SELECT COUNT(*) FROM users WHERE is_profile_complete AND NOT is_blocked) AS profiles_complete,
    (SELECT COUNT(*) FROM events WHERE status = 'published' AND NOT is_deleted AND starts_at > NOW()) AS upcoming_events,
    (SELECT COUNT(*) FROM event_registrations
     WHERE registered_at >= DATE_TRUNC('week', NOW()) AND status IN ('registered','confirmed')) AS registrations_this_week,
    (SELECT COUNT(*) FROM team_join_applications WHERE status = 'new') AS pending_team_apps,
    (SELECT COUNT(*) FROM space_booking_requests WHERE status = 'new') AS pending_bookings,
    (SELECT COUNT(*) FROM messages WHERE status = 'new') AS unread_messages,
    (SELECT COUNT(*) FROM contact_form_submissions WHERE status = 'new') AS unread_contacts;

COMMENT ON VIEW v_dashboard_stats IS 'Лічильники дашборда платформи';


-- 6.4 Календар бронювань
CREATE OR REPLACE VIEW v_booking_calendar AS
SELECT
    sbr.id, sbr.event_name, sbr.booking_date,
    sbr.start_time, sbr.end_time, sbr.status,
    sbr.contact_name, s.name AS space_name, s.slug AS space_slug
FROM space_booking_requests sbr
JOIN spaces s ON sbr.space_id = s.id
WHERE sbr.status IN ('new','reviewing','confirmed')
ORDER BY sbr.booking_date, sbr.start_time;

COMMENT ON VIEW v_booking_calendar IS 'Календарне представлення бронювань';


-- 6.5 Топ-10 активних учасників
CREATE OR REPLACE VIEW v_top_active_users AS
SELECT
    u.id, u.first_name, u.last_name, u.telegram_username,
    ul.name AS level_name, u.visit_count,
    COUNT(DISTINCT er.event_id) AS total_registrations,
    COUNT(DISTINCT ea.event_id) FILTER (WHERE ea.attended) AS total_attended,
    COUNT(DISTINCT f.id) AS total_feedbacks,
    u.bot_started_at
FROM users u
LEFT JOIN user_levels ul ON u.level_id = ul.id
LEFT JOIN event_registrations er ON u.id = er.user_id AND er.status != 'cancelled'
LEFT JOIN event_attendance ea ON u.id = ea.user_id AND ea.attended
LEFT JOIN feedbacks f ON u.id = f.user_id
WHERE NOT u.is_blocked AND u.is_active
GROUP BY u.id, u.first_name, u.last_name, u.telegram_username,
         ul.name, u.visit_count, u.bot_started_at
ORDER BY u.visit_count DESC
LIMIT 10;

COMMENT ON VIEW v_top_active_users IS 'Топ-10 найактивніших відвідувачів';


-- ============================================================
-- 7. ТРИГЕРНІ ФУНКЦІЇ БІЗНЕС-ЛОГІКИ
-- ============================================================

-- 7.1 Автоматичне оновлення рівня користувача
CREATE OR REPLACE FUNCTION fn_auto_update_user_level()
RETURNS TRIGGER AS $$
DECLARE
    new_level_id UUID;
BEGIN
    SELECT id INTO new_level_id
    FROM user_levels
    WHERE is_active = TRUE
      AND NEW.visit_count >= min_visits
      AND (max_visits IS NULL OR NEW.visit_count <= max_visits)
    ORDER BY min_visits DESC
    LIMIT 1;

    IF new_level_id IS DISTINCT FROM NEW.level_id THEN
        NEW.level_id = new_level_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_auto_level
    BEFORE INSERT OR UPDATE OF visit_count ON users
    FOR EACH ROW EXECUTE FUNCTION fn_auto_update_user_level();


-- 7.2 Автопросування з черги очікування
CREATE OR REPLACE FUNCTION fn_promote_from_waitlist()
RETURNS TRIGGER AS $$
DECLARE
    v_next UUID;
    v_limit INT;
    v_current INT;
BEGIN
    IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
        SELECT participant_limit INTO v_limit FROM events WHERE id = NEW.event_id;

        IF v_limit > 0 THEN
            SELECT COUNT(*) INTO v_current
            FROM event_registrations
            WHERE event_id = NEW.event_id AND status IN ('registered','confirmed');

            IF v_current < v_limit THEN
                SELECT id INTO v_next
                FROM event_registrations
                WHERE event_id = NEW.event_id AND status = 'waitlisted'
                ORDER BY waitlist_position ASC
                LIMIT 1;

                IF v_next IS NOT NULL THEN
                    UPDATE event_registrations
                    SET status = 'registered',
                        waitlist_position = NULL,
                        promoted_from_waitlist_at = NOW()
                    WHERE id = v_next;
                END IF;
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_event_reg_promote_waitlist
    AFTER UPDATE ON event_registrations
    FOR EACH ROW EXECUTE FUNCTION fn_promote_from_waitlist();


-- 7.3 Оновлення visit_count при відмітці присутності
CREATE OR REPLACE FUNCTION fn_update_visit_count()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.attended = TRUE AND (OLD.attended IS NULL OR OLD.attended = FALSE) THEN
        UPDATE users SET visit_count = visit_count + 1 WHERE id = NEW.user_id;
    ELSIF NEW.attended = FALSE AND OLD.attended = TRUE THEN
        UPDATE users SET visit_count = GREATEST(visit_count - 1, 0) WHERE id = NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_attendance_visit_count
    AFTER INSERT OR UPDATE OF attended ON event_attendance
    FOR EACH ROW EXECUTE FUNCTION fn_update_visit_count();


-- 7.4 Автоматична зміна статусу повідомлення при відповіді
CREATE OR REPLACE FUNCTION fn_message_auto_status()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE messages SET status = 'replied' WHERE id = NEW.message_id AND status != 'replied';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_message_reply_status
    AFTER INSERT ON message_replies
    FOR EACH ROW EXECUTE FUNCTION fn_message_auto_status();


-- 7.5 Автоматичне визначення is_profile_complete
CREATE OR REPLACE FUNCTION fn_check_profile_complete()
RETURNS TRIGGER AS $$
BEGIN
    NEW.is_profile_complete = (
        NEW.first_name IS NOT NULL AND NEW.first_name != ''
        AND NEW.last_name IS NOT NULL AND NEW.last_name != ''
        AND NEW.phone IS NOT NULL AND NEW.phone != ''
        AND NEW.birth_date IS NOT NULL
    );

    IF NEW.is_profile_complete = TRUE AND (OLD.is_profile_complete IS NULL OR OLD.is_profile_complete = FALSE) THEN
        NEW.registered_at = COALESCE(NEW.registered_at, NOW());
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_profile_check
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_check_profile_complete();


-- ============================================================
-- 8. УТИЛІТНІ ФУНКЦІЇ
-- ============================================================

-- 8.1 Очищення протермінованого кошика
CREATE OR REPLACE FUNCTION fn_cleanup_expired_trash()
RETURNS INT AS $$
DECLARE cnt INT;
BEGIN
    DELETE FROM trash_bin WHERE expires_at < NOW() AND NOT is_restored;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    RETURN cnt;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_cleanup_expired_trash IS 'Видалення записів з кошика старших 30 днів';


-- 8.2 Деактивація протермінованих сесій
CREATE OR REPLACE FUNCTION fn_cleanup_expired_sessions()
RETURNS INT AS $$
DECLARE cnt INT;
BEGIN
    UPDATE admin_sessions SET is_active = FALSE WHERE is_active = TRUE AND expires_at < NOW();
    GET DIAGNOSTICS cnt = ROW_COUNT;
    RETURN cnt;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_cleanup_expired_sessions IS 'Деактивація сесій з тайм-аутом 8 годин';


-- 8.3 Протермінування запрошень
CREATE OR REPLACE FUNCTION fn_expire_invitations()
RETURNS INT AS $$
DECLARE cnt INT;
BEGIN
    UPDATE admin_invitations SET status = 'expired' WHERE status = 'pending' AND expires_at < NOW();
    GET DIAGNOSTICS cnt = ROW_COUNT;
    RETURN cnt;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_expire_invitations IS 'Протермінування запрошень на платформу';


-- 8.4 Автозавершення заходів
CREATE OR REPLACE FUNCTION fn_complete_past_events()
RETURNS INT AS $$
DECLARE cnt INT;
BEGIN
    UPDATE events SET status = 'completed'
    WHERE status = 'published' AND ends_at < NOW() AND NOT is_deleted;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    RETURN cnt;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_complete_past_events IS 'Автоматичне завершення минулих заходів';


-- 8.5 Оновлення прапорця активності користувачів
CREATE OR REPLACE FUNCTION fn_update_user_activity_flags()
RETURNS INT AS $$
DECLARE cnt INT;
BEGIN
    UPDATE users SET is_active = FALSE
    WHERE is_active = TRUE
      AND last_activity_at < NOW() - INTERVAL '30 days'
      AND NOT is_blocked;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    RETURN cnt;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_update_user_activity_flags IS 'Позначка неактивних користувачів (>30 днів)';


-- ============================================================
-- КІНЕЦЬ СКРИПТУ
-- ============================================================
-- Підсумок:
--   Таблиць:         47
--   ENUM типів:      30
--   Індексів:        75+
--   Тригерів:        20+
--   Представлень:    5
--   Бізнес-функцій:  10
--   Seed-записів:    35+
-- ============================================================
