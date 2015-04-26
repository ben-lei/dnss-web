package dnss.controller;

import dnss.model.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Controller;
import org.springframework.ui.ModelMap;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.context.WebApplicationContext;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.util.ArrayList;

import static javax.servlet.http.HttpServletResponse.SC_NOT_FOUND;

@Controller
@RequestMapping("/download")
public class DownloadController {
    @Autowired
    private WebApplicationContext context;

    @Autowired
    private SP sp;

    @RequestMapping("/{alignment:[h|v]}/{identifiers:[a-z,]+}/{level:[1-9][0-9]*}/{build:[0-9a-zA-Z-\\.\\+]{48,}}")
    public String download(HttpServletRequest request, HttpServletResponse response,
                           @PathVariable("identifiers") String identifiers,
                           @PathVariable("level") int level,
                           @PathVariable("build") String query,
                           @PathVariable("alignment") String alignment,
                           ModelMap model) throws Exception {
        String[] r = identifiers.split(",");
        if (r.length < 1 || r.length > 3) { // will do next release
            response.sendError(SC_NOT_FOUND, "Not supported");
        }

        // first make sure they are all valid jobs
        ArrayList<Job> list = new ArrayList<Job>();
        for (String s : r) {
            if (!context.containsBean("job_" + s)) {
                response.sendError(SC_NOT_FOUND, "No job '"+s+"'");
            }

            list.add((Job)context.getBean("job_" + s));
        }

        Jobs jobs = sortJobList(list);

        if (jobs == null || ! jobs.isValid()) {
            response.sendError(SC_NOT_FOUND, "Invalid job list");
        }

        // just any tertiary jobs
        Job tertiary = (Job)context.getBean("job_gladiator");

        // set the level+sp cap
        jobs.setLevel(level);
        jobs.setMaxSP(sp.forCap(level), tertiary.getSpRatio());

        Build build = new Build(query);

        int pos = 0;
        for (Job job : jobs) {
            if (job == null) {
                pos += 24;
                continue;
            }

            for (int i = 0; i < 24; i++, pos++) {
                Skill skill = job.getSkill(i);
                if (skill == null) {
                    continue;
                }

                skill.setLevel(build.get(pos));
//                System.out.println(skill.getId() + " - level " + skill.getLevel());
            }
        }

        model.addAttribute("alignment", alignment);
        model.addAttribute("jobs", jobs);


        return "download";
    }


    private Jobs sortJobList(ArrayList<Job> list) {
        Jobs jobs = new Jobs();

        for (Job j : list) {
            if (jobs.getJob(j.getAdvancement()) == null) {
                jobs.setJob(j);
            } else {
                return null;
            }
        }

        return jobs;
    }

}