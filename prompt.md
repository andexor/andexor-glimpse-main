# Glimpse

Build me a re-usable system I can use to totally automate this process from end-to-end with everything you have suggested. This will be a system that creates systems. Start by writing a master PRD with a checklist using the info from this chat and add the following info to it. Let's iteratively review and refine it until you and I are both satisfied that it is ready for implementation. The actual implementation will be split into 2 or more fully independent systems, like what we did with andexor-net-website for the front-end and andexor-net-website-contact-us for the back-end.

The base name of the system is to be called "Andexor Glimpse". The name is based on a concept taken from the movie [The Family Man](https://www.imdb.com/title/tt0218967/). The ID to use for repo names, app names, etc. should start with "andexor-glimpse", followed by a dash and then a descriptive name like "fe" for front-end, "be" for back-end, etc. Or we could go with "ui" and "server". Choose what makes the most sense and remember it for future multi-tiered projects like this. We need to establish some kind of standard naming convention. Note that:

1. There will be multiple front-end apps.
   - I need an admin UI for me to manage these glimpses.
   - Customers need an admin UI they can use to approve or decline and add comments.
   - Each glimpse itself needs a UI.
1. For back-end systems, we will start with
   - One server app for me to manage the glimpses.
   - One server app for prospects, which will be used by their admin UI.
   - One server app for each glimpse.
   - Expect the possibility that we might extend this in the future to add more back-end services to enrich the process of creating and managing glimpses.

Split the master PRD into separate units, one for each project you create for the apps that will manage and run this system, keeping the master PRD to govern them all.

A glimpse is a preview of what a website could look like. It is given to a prospect who either currently has no website or has one that needs to be upgraded and modernized with a new look, more security, better performance, better accessibility, or uses AI to help their customers buy from them.

It is used to invite a prospect to see an example of what we can build for them. Once they see it, they can choose whether they want us to implement it if they like it, or drop it if they decline.

This system needs to support multiple glimpses live at any given time and keep each one fully isolated from all others.

## Getting Started

The only inputs you need from me are

- company name
- owner's name
- phone number
- email address

The company name is the only required field. The others are optional.

Use the GitHub MCP server and the gh CLI as needed. Make sure you are logged in as me.

Use the Cloudflare MCP server, wrangler, and cf commands as needed.
Make sure you are logged in to my Cloudflare account and everything is working by using some simple read-only command that only works when logged in.

Use Spec Kit to manage requirements for this system and for the glimpses that it creates.

## Repositories

For this system, I want you to write a script in Python that can automate the creation of code repositories in GitHub in a consistent manner. Review the following settings in [andexor-net-website](https://github.com/andexor/andexor-net-website) and select all of the same kinds of options for each new repository:

- Begin each new repo by using [andexor-base-template](https://github.com/andexor/andexor-base-template) as a template.
- Select all of the same options that appear on the "Security and quality" tab.
- Select all of the same kinds of options that appear on the "Settings" tab, noting that the "Repository name" will be different of course. Be sure to include:
  - Preserve this repository
  - Allow squash merging
  - Limit how many branches and tags can be updated in a single push
  - Automatically delete head branches
  - Rulesets
  - Advanced Security
- The new repositories will not be used as a template, so do not select that option when creating them.
- Install appropriate GitHub actions for the new repos, using whatever is appropriate for TypeScript on front-end apps and Python for back-end apps.

Actually, this should not be a script for me to run manually. All of this functionality needs to be part of the back-end part of my admin system used to create and manage glimpses via my front-end admin app.

**Important**: Make sure ALL repos you create for the system and the glimpses are placed in the andexor namespace, not the ejenkins namespace.

**Important**: The repos for the system should be made public, but when the system creates repos for glimpses, those must be made private.

After any repo is created, star it for me and then set it to watch all activity.

## Platforms

- Use the existing nvm and Node and use the latest Next.js to create the front-end UI apps. Use NodeJS for easy integration with Cloudflare. Don't bother with Bun or Docker unless we find a good reason to include them.
- Since these are full-on web apps, use Client Side Rendering (CSR) for the front-end apps.
- Since these are for internal use and for use by prospects, they should block robots. We do not need a sitemap. All links should be nofollow, noindex.
- Use the existing uv and Python and use the latest FastAPI for the back-end apps like we did for [andexor-net-website-contact-us](https://github.com/andexor/andexor-net-website-contact-us).
- Everything is to be deployed to Cloudflare.
- Store data in a Cloudflare D1 database.

## Behavior

- Add initial support for Cookibot like we did in [andexor-net-website](https://github.com/andexor/andexor-net-website). We'll test it to see if it works with these apps too.
- Use FontAwesome and the same Google Fonts and Andexor Network Design System that we used in andexor-net-website for this system that creates and manages glimpses (my admin UI and the prospects' admin UI), but not for the glimpses themselves.
- Make sure all apps are co-ordinated to be responsive. Wherever there is a form submit button that calls a REST API, let the button go down and up before submitting. Test the back-end systems for performance. If the operation is going to take more than 1 second to complete, consider sending a message and making the process asynchronous, using SSE to inform the front-end of the progress.
- When generating a glimpse, once a repo has been created from the template, create only a simple, minimal "Hello World" app. I will replace the content with a real design preview as a manual step after all of these automated setup procedures have completed.
- After I create the real design content, I need a way to notify the prospect that I have created a preview for them to consider. I should be able to contact them either via SMS or email, depending on what information is available. Stub out the basic features for this now. Let me customize separate templates for email and SMS and give you the plumbing details later, after I get that kind of functionality operational.
- The customer needs to be able to approve or reject the design proposal and add as many comments as they want. All of this needs to go into the database, making sure to keep each glimpse isolated from other ones. Create a data model to make this happen. Whenever they submit feedback, I need to be notified by email and SMS. Stub it for now, details to come later.
- Each glimpse needs to be live for 7 days. After that time, it should expire automatically. When that happens, keep the content handy in the private repo, but remove access to the glimpse for the prospect. After 30 days, delete the private repo. All of these are scheduled events that need to run on a cron schedule. Show me the dates for these events in my admin UI and the prospect's admin UI. We should only see the date and time, not the cron expression. The cron expression should be viewable in the database so I don't have to hunt for it in the Cloudflare console.
- Allow me to grant access again for another 7 days if the prospect asks me to bring it back anytime later.
- Allow me to request that the glimpse be deleted if the customer approves and it goes live or if they decline.
- Note that the same customer could decline one day and come back again with a yes sometime later. If the glimpse is gone, let's create a new one for them then.
- In the main repository that governs all of the related repos for the Andexor Glimpse system (not the glimpse projects themselves), go ahead and create PlantUML diagrams like we did in [andexor-grass-spider-rdap-module](https://github.com/andexor/andexor-grass-spider-rdap-module).
