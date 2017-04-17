# Zendesk-Data-Collector

This app uses Zendesk's Incremental TIckets API to populate a postgres DB table with every data point available via that API.

[![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy)

During deployment, you will configure an admin user account.  This is used to login to the system.  Once logged in, you will add your Zendesk accounts with a username and API token.  

If your desk is "active" in the admin panel, the system will collect data from the API and populate the a table in the postgres database.