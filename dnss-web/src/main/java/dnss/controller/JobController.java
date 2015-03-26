package dnss.controller;

import dnss.model.Job;
import dnss.enums.Advancement;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Controller;
import org.springframework.ui.ModelMap;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.context.WebApplicationContext;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.ArrayList;
import java.util.LinkedList;

@Controller
@RequestMapping("/job")
public class JobController {
    @Autowired
    private WebApplicationContext context;

    @RequestMapping("/{job_identifier}")
    public String hello(HttpServletResponse response,
                        @PathVariable("job_identifier") String jobIdentifier,
                        ModelMap model) throws IOException {
        String bean = "job_"  +jobIdentifier;
        if (! context.containsBean(bean)) {
            response.sendError(HttpServletResponse.SC_NOT_FOUND, "No job '" + jobIdentifier + "'");
        }

        ArrayList<Integer> levels = (ArrayList<Integer>)context.getBean("levels");
        int maxSP = levels.get(levels.size() - 1);

        LinkedList<Job> jobList = new LinkedList<Job>();
        try {
            Job job = (Job)context.getBean(bean);
            float[] spRatios = job.getSpRatio();
            for (int i = spRatios.length - 1; job != null; i--) {
                job.setMaxSP((int)(maxSP * spRatios[i]));
                jobList.addFirst(job);
                job = job.getParent();
            }
        } catch (Exception e) {
            response.sendError(HttpServletResponse.SC_NOT_FOUND, e.getMessage());
        }

        if (jobList.size() != 3) {
            response.sendError(HttpServletResponse.SC_FORBIDDEN, jobList.getLast().getName() + " is not allowed to be simulatled.");
        }

        model.addAttribute("jobs", jobList);
        model.addAttribute("max_sp", maxSP);


        return "home";
    }
}