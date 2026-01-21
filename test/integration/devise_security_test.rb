require "test_helper"

class DeviseSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @admin_user = AdminUser.create!(
      email: "security@example.com",
      password: "securepassword123",
      password_confirmation: "securepassword123"
    )
  end

  test "account locks after maximum failed login attempts" do
    visit new_admin_user_session_path

    # Attempt to sign in 5 times with wrong password (maximum_attempts = 5)
    5.times do
      fill_in "Email", with: @admin_user.email
      fill_in "Password", with: "wrongpassword123"
      click_button "Log in"
    end

    # Reload the admin user to check the lock status
    @admin_user.reload
    assert @admin_user.locked_at.present?, "Account should be locked after 5 failed attempts"
    assert_equal 5, @admin_user.failed_attempts, "Failed attempts should be 5"
  end

  test "password must be at least 12 characters" do
    # Try to create admin user with short password
    short_password_user = AdminUser.new(
      email: "short@example.com",
      password: "short123",
      password_confirmation: "short123"
    )

    assert_not short_password_user.valid?, "User should not be valid with password less than 12 characters"
    assert_includes short_password_user.errors[:password], "is too short (minimum is 12 characters)"
  end

  test "password with 12 characters is valid" do
    valid_password_user = AdminUser.new(
      email: "valid@example.com",
      password: "validpass123",
      password_confirmation: "validpass123"
    )

    assert valid_password_user.valid?, "User should be valid with 12 character password"
  end

  test "successful login resets failed attempts counter" do
    # Fail once
    visit new_admin_user_session_path
    fill_in "Email", with: @admin_user.email
    fill_in "Password", with: "wrongpassword123"
    click_button "Log in"

    @admin_user.reload
    assert_equal 1, @admin_user.failed_attempts, "Failed attempts should be 1 after failed login"

    # Now login successfully
    fill_in "Email", with: @admin_user.email
    fill_in "Password", with: "securepassword123"
    click_button "Log in"

    assert_text(/Signed in successfully/i)

    @admin_user.reload
    assert_equal 0, @admin_user.failed_attempts, "Failed attempts should be reset to 0 after successful login"
  end
end
