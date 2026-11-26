package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"golang.org/x/crypto/bcrypt"
)

const (
	AccessTokenTTL  = 2 * time.Hour
	RefreshTokenTTL = 30 * 24 * time.Hour

	RoleSystemAdmin = "system_admin"
	RoleManager     = "manager"
	RoleTechnician  = "technician"
	RoleClient      = "client"
)

// Pre-computed dummy bcrypt hash used when a login email does not exist,
// preventing timing side-channels that could enumerate valid accounts.
var dummyBcryptHash = func() []byte {
	h, _ := bcrypt.GenerateFromPassword([]byte("dummy-timing-protection-password"), bcrypt.DefaultCost)
	return h
}()

type AccessTokenClaims struct {
	Role               string `json:"role"`
	CompanyID          string `json:"company_id,omitempty"`
	MustChangePassword bool   `json:"must_change_password"`
	jwt.RegisteredClaims
}

type TokenManager struct {
	secret []byte
}

func NewTokenManager(secret string) *TokenManager {
	return &TokenManager{secret: []byte(secret)}
}

func (tm *TokenManager) GenerateAccessToken(sessionID pgtype.UUID, userID pgtype.UUID, companyID pgtype.UUID, role string, mustChangePassword bool, now time.Time) (string, time.Time, error) {
	if !sessionID.Valid || !userID.Valid {
		return "", time.Time{}, errors.New("invalid session or user ID")
	}

	expiresAt := now.UTC().Add(AccessTokenTTL)
	claims := AccessTokenClaims{
		Role:               role,
		MustChangePassword: mustChangePassword,
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        FormatUUID(sessionID),
			Subject:   FormatUUID(userID),
			IssuedAt:  jwt.NewNumericDate(now.UTC()),
			ExpiresAt: jwt.NewNumericDate(expiresAt),
		},
	}
	if companyID.Valid {
		claims.CompanyID = FormatUUID(companyID)
	}

	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := tok.SignedString(tm.secret)
	if err != nil {
		return "", time.Time{}, err
	}
	return signed, expiresAt, nil
}

func (tm *TokenManager) ParseAccessToken(tokenStr string) (*AccessTokenClaims, pgtype.UUID, pgtype.UUID, error) {
	claims := &AccessTokenClaims{}
	parsed, err := jwt.ParseWithClaims(tokenStr, claims, func(t *jwt.Token) (any, error) {
		if t.Method.Alg() != jwt.SigningMethodHS256.Alg() {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return tm.secret, nil
	}, jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}))
	if err != nil || !parsed.Valid {
		return nil, pgtype.UUID{}, pgtype.UUID{}, errors.New("invalid or expired access token")
	}

	userUUID, err := ParseUUID(claims.Subject)
	if err != nil {
		return nil, pgtype.UUID{}, pgtype.UUID{}, errors.New("invalid subject in access token")
	}

	sessionUUID, err := ParseUUID(claims.ID)
	if err != nil {
		return nil, pgtype.UUID{}, pgtype.UUID{}, errors.New("invalid session ID in access token")
	}

	return claims, userUUID, sessionUUID, nil
}

func GenerateRefreshToken() (rawToken string, tokenHash string, err error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", "", err
	}
	rawToken = base64.RawURLEncoding.EncodeToString(buf)
	tokenHash = HashRefreshToken(rawToken)
	return rawToken, tokenHash, nil
}

func HashRefreshToken(rawToken string) string {
	sum := sha256.Sum256([]byte(rawToken))
	return hex.EncodeToString(sum[:])
}

func GenerateTemporaryPassword() (string, error) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

func HashPassword(plain string) (string, error) {
	if len(plain) < 8 {
		return "", errors.New("password must be at least 8 characters long")
	}
	if len([]byte(plain)) > 72 {
		return "", errors.New("password must not exceed 72 bytes")
	}
	b, err := bcrypt.GenerateFromPassword([]byte(plain), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func ComparePassword(hash, plain string) error {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(plain))
}

func DummyComparePassword(plain string) {
	_ = bcrypt.CompareHashAndPassword(dummyBcryptHash, []byte(plain))
}

func FormatUUID(u pgtype.UUID) string {
	if !u.Valid {
		return ""
	}
	b := u.Bytes
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

func ParseUUID(s string) (pgtype.UUID, error) {
	var u pgtype.UUID
	if err := u.Scan(s); err != nil || !u.Valid {
		return pgtype.UUID{}, fmt.Errorf("invalid UUID %q", s)
	}
	return u, nil
}
