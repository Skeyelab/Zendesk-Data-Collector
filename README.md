# Zendesk-Data-Collector

This Heroku Button will setup a Rails app with a Postgres DB. Once you put your Zendesk info into the app, it will extract all ticket data in real time to the DB.  It will create all columns needed, even when a new custom field is created.

[![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy)

The point of this app is to then attach a reporting package to the database to create fully customized, real time reports.

During deployment, you will configure an admin user account.  This is used to login to the system at https://YOUR_APP.herokuapp.com/admin/login.  Once logged in, you will add your Zendesk accounts with a username and API token. 

If your desk is "active" in the admin panel, the system will collect data from the API and populate the a table in the postgres database.  

At this point you can use your reporting tool of choice with the DB.  You can find the connection info in your Heroku Config Variables.
