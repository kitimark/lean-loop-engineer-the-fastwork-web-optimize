/**
 * Reviews and About content of the People section for the six showcase professions (the original's profile list,
 * nodes/2.DyWL8TcE.js 4828-6131; the review rows are the original's `SD` expansion of its review texts, the dimension scores
 * its `CD`). Text and numbers restated; picture names are files of snapshot/site/selling/sellers/<profile-id>/ (logos, review
 * photos) and sellers/reviewers/ (author avatars), resolved by ./assets.
 */
export interface ReviewItem {
  id: string;
  score: number;
  text: string;
  images: string[];
  author: { name: string; avatar: string };
  serviceId: string;
  date: string;
}
export interface Reviews {
  score: number;
  total: number;
  dimensions: { responseSpeed: number; serviceQuality: number; skill: number; value: number };
  summary: string[];
  items: ReviewItem[];
}
export interface Experience {
  id: string;
  logo?: string;
  role: string;
  company: string;
  summary?: string;
  start: string;
  end: string | null;
}
export interface Education {
  id: string;
  logo?: string;
  school: string;
  degree: string;
  field?: string;
  start?: string;
  end?: string;
}
export interface Certificate {
  id: string;
  logo?: string;
  title: string;
  issued: string;
  issuer: string;
}
export interface Language {
  id: string;
  name: string;
  level: string;
}
export interface About {
  experience: Experience[];
  education: Education[];
  skills: string[];
  certificates: Certificate[];
  languages: Language[];
  awards: string[];
}
export interface PanelData {
  reviews: Reviews;
  about: About;
}

export const PANELS: Record<string, PanelData> = {
  "sound-composer": {
    "reviews": {
      "score": 4.8,
      "total": 30,
      "dimensions": {
        "responseSpeed": 4.8,
        "serviceQuality": 4.8,
        "skill": 4.9,
        "value": 4.7
      },
      "summary": [
        "Phil’s score completely elevated our film — he captured the exact emotional depth and vision we needed.",
        "Super professional workflow and world-class mixing quality.",
        "He delivered a cinematic experience that exceeded all our expectations."
      ],
      "items": [
        {
          "id": "r1",
          "score": 5,
          "text": "Exceptional storytelling through sound; his compositions bring scenes to life flawlessly.",
          "images": [
            "post-orchestra.jpg"
          ],
          "author": {
            "name": "Sorawit K.",
            "avatar": "r11.jpg"
          },
          "serviceId": "feature-score",
          "date": "2026-09-04"
        },
        {
          "id": "r2",
          "score": 4.5,
          "text": "Outstanding sound design and orchestration techniques.",
          "images": [],
          "author": {
            "name": "Kanyarat L.",
            "avatar": "r12.jpg"
          },
          "serviceId": "short-film-scoring",
          "date": "2026-08-21"
        },
        {
          "id": "r3",
          "score": 5,
          "text": "The soundtrack release was handled end to end, from stems to streaming platforms, without us lifting a finger.",
          "images": [
            "post-spotify.jpg"
          ],
          "author": {
            "name": "Chutima K.",
            "avatar": "r1.jpg"
          },
          "serviceId": "soundtrack-release",
          "date": "2026-08-02"
        }
      ]
    },
    "about": {
      "experience": [
        {
          "id": "film-composer",
          "role": "Film Composer & Sound Designer",
          "company": "Freelance · feature films, series & documentaries",
          "summary": "Scores for over twenty features and series across Thailand and Asia, selected for Cannes, Berlinale, BFI London, Busan and Hong Kong.",
          "start": "2012-01",
          "end": null
        },
        {
          "id": "phil-wc",
          "role": "Ambient & Experimental Music Producer",
          "company": "phil_wc · artist project",
          "summary": "Releases on Spotify, Apple Music and Tidal, drawing on EDM, progressive and avant-garde influences.",
          "start": "2015-01",
          "end": null
        }
      ],
      "education": [
        {
          "id": "ucla",
          "school": "UCLA Extension, USA",
          "degree": "Film Scoring"
        },
        {
          "id": "rangsit",
          "school": "Rangsit University, Thailand",
          "degree": "Bachelor’s Degree in Music Composition"
        },
        {
          "id": "filmsound-hamburg",
          "school": "FilmSoundHamburg, Germany",
          "degree": "Film Scoring and Sound Design Workshop (scholarship)",
          "field": "with Jan A. P. Kaczmarek and James Mather",
          "start": "2012-01",
          "end": "2012-12"
        }
      ],
      "skills": [
        "Film Scoring & Original Soundtracks",
        "Orchestral Composition",
        "Sound Design",
        "Ambient & Experimental Music"
      ],
      "certificates": [],
      "languages": [
        {
          "id": "th",
          "name": "Thai",
          "level": "Native or bilingual proficiency"
        },
        {
          "id": "en",
          "name": "English",
          "level": "Professional working proficiency"
        }
      ],
      "awards": [
        "Best Original Score — You & Me & Me, Suphannahong National Film Awards (2024)",
        "Best Original Score — Mother Gamer, Thai Film Director Awards (2021)",
        "Best Original Score — Malila The Farewell Flower, Starpics Thai Film Awards (2019)",
        "Best Original Score — Malila The Farewell Flower, Bangkok Critics Assembly (2019)",
        "Best Original Score — The Blue Hour, Starpics Thai Film Awards (2016)",
        "Best Original Score — The Blue Hour, Bangkok Critics Assembly (2016)",
        "IDA Documentary Awards nominee — Hope Frozen (2020)"
      ]
    }
  },
  "photographer": {
    "reviews": {
      "score": 4.9,
      "total": 47,
      "dimensions": {
        "responseSpeed": 4.9,
        "serviceQuality": 4.9,
        "skill": 5,
        "value": 4.8
      },
      "summary": [
        "A distinct visual style that makes every campaign feel premium",
        "Full production handled end to end, from concept to final retouch"
      ],
      "items": [
        {
          "id": "r1",
          "score": 5,
          "text": "The product shots looked like a magazine spread. Our conversion on the launch page went up right away.",
          "images": [
            "post-tuna-cut.jpg"
          ],
          "author": {
            "name": "Thanakrit P.",
            "avatar": "r10.jpg"
          },
          "serviceId": "commercial-shoot",
          "date": "2026-09-04"
        },
        {
          "id": "r2",
          "score": 4.5,
          "text": "Creative direction, styling and crew all in one team. The lookbook came out exactly as we imagined.",
          "images": [
            "post-loreal.jpg",
            "post-runway.jpg"
          ],
          "author": {
            "name": "Sorawit K.",
            "avatar": "r11.jpg"
          },
          "serviceId": "fashion-shoot",
          "date": "2026-08-21"
        },
        {
          "id": "r3",
          "score": 5,
          "text": "Covered our two-day event and had social clips ready the next morning. Super professional.",
          "images": [],
          "author": {
            "name": "Kanyarat L.",
            "avatar": "r12.jpg"
          },
          "serviceId": "event-content",
          "date": "2026-08-02"
        }
      ]
    },
    "about": {
      "experience": [
        {
          "id": "dopeeyes",
          "logo": "avatar.jpg",
          "role": "Founder & Lead Photographer",
          "company": "Karn Kraipasit",
          "summary": "Production house for commercial, fashion and food photography, social media content, KOL campaigns and event coverage.",
          "start": "2019-03",
          "end": null
        },
        {
          "id": "freelance",
          "role": "Freelance Photographer",
          "company": "Self-employed",
          "start": "2015-06",
          "end": "2019-02"
        }
      ],
      "education": [],
      "skills": [
        "Commercial Photography",
        "Fashion & Editorial",
        "Food & Product",
        "Video Production",
        "Social Media Content"
      ],
      "certificates": [],
      "languages": [],
      "awards": []
    }
  },
  "video-editor": {
    "reviews": {
      "score": 4.9,
      "total": 25,
      "dimensions": {
        "responseSpeed": 4.9,
        "serviceQuality": 4.9,
        "skill": 5,
        "value": 4.8
      },
      "summary": [
        "Bank finds the rhythm of the footage and cuts to the music like nobody else.",
        "Fast turnaround on shorts without losing the cinematic look."
      ],
      "items": [
        {
          "id": "r1",
          "score": 5,
          "text": "The aftermovie captured the whole night in ninety seconds. Our followers asked for the full version.",
          "images": [
            "post-club.jpg"
          ],
          "author": {
            "name": "Thanakrit P.",
            "avatar": "r10.jpg"
          },
          "serviceId": "cinematic-edit",
          "date": "2026-09-04"
        },
        {
          "id": "r2",
          "score": 4.5,
          "text": "Delivered a set of Reels the day after the shoot, each one graded and synced to the track.",
          "images": [
            "post-oym.jpg"
          ],
          "author": {
            "name": "Sorawit K.",
            "avatar": "r11.jpg"
          },
          "serviceId": "shorts-edit",
          "date": "2026-08-21"
        },
        {
          "id": "r3",
          "score": 5,
          "text": "The music video edit had real pacing and mood. We would book him again for the next release.",
          "images": [],
          "author": {
            "name": "Kanyarat L.",
            "avatar": "r12.jpg"
          },
          "serviceId": "cinematic-edit",
          "date": "2026-08-02"
        }
      ]
    },
    "about": {
      "experience": [
        {
          "id": "freelance",
          "role": "Freelance Video Editor",
          "company": "Self-employed",
          "summary": "VTR, music videos, aftermovies, trailers, teasers and short-form content for brands, artists and event organisers.",
          "start": "2021-01",
          "end": null
        },
        {
          "id": "production-house",
          "role": "Junior Editor",
          "company": "Production house, Bangkok",
          "start": "2018-06",
          "end": "2020-12"
        }
      ],
      "education": [],
      "skills": [
        "Video Editing",
        "Color Grading",
        "Sound Design",
        "Motion Graphics",
        "Short-Form Content"
      ],
      "certificates": [],
      "languages": [],
      "awards": []
    }
  },
  "graphic-designer": {
    "reviews": {
      "score": 4.8,
      "total": 20,
      "dimensions": {
        "responseSpeed": 4.8,
        "serviceQuality": 4.8,
        "skill": 4.9,
        "value": 4.7
      },
      "summary": [
        "Creative ideas that bring each brand’s story to life",
        "Outstanding illustration and layout work"
      ],
      "items": [
        {
          "id": "r1",
          "score": 5,
          "text": "Delivered excellent graphic design for our social media campaign",
          "images": [
            "post-fraction.jpg"
          ],
          "author": {
            "name": "Nattaya S.",
            "avatar": "r7.jpg"
          },
          "serviceId": "graphic-design",
          "date": "2026-09-04"
        },
        {
          "id": "r2",
          "score": 4.5,
          "text": "Really impressed with the illustration style and creative direction.",
          "images": [
            "post-nefertem.jpg",
            "post-dream-team.jpg"
          ],
          "author": {
            "name": "Thanawat R.",
            "avatar": "r8.jpg"
          },
          "serviceId": "illustration",
          "date": "2026-08-21"
        },
        {
          "id": "r3",
          "score": 5,
          "text": "The design is so creative and professional",
          "images": [],
          "author": {
            "name": "Patcharapa W.",
            "avatar": "r9.jpg"
          },
          "serviceId": "graphic-design",
          "date": "2026-08-02"
        }
      ]
    },
    "about": {
      "experience": [
        {
          "id": "fastwork",
          "logo": "logo-fastwork.png",
          "role": "Lead Designer & Art Director",
          "company": "Fastwork.co",
          "start": "2026-01",
          "end": null
        },
        {
          "id": "buddybbb",
          "role": "Art Director",
          "company": "BuddyBBB",
          "start": "2024-04",
          "end": null
        },
        {
          "id": "supara",
          "logo": "logo-supara.jpg",
          "role": "Art Director",
          "company": "Supara Group",
          "start": "2021-03",
          "end": "2021-10"
        },
        {
          "id": "sf",
          "logo": "logo-sf.jpg",
          "role": "Brand Design Manager",
          "company": "SF Corporation",
          "start": "2019-10",
          "end": "2021-02"
        },
        {
          "id": "moonshot",
          "role": "Senior Graphic Designer",
          "company": "Moonshot Digital Co.,Ltd. (Rabbit Digital Group)",
          "start": "2017-10",
          "end": "2019-05"
        }
      ],
      "education": [
        {
          "id": "chula",
          "logo": "logo-chula.jpg",
          "school": "Chulalongkorn University",
          "degree": "Bachelor of Fine and Applied Arts",
          "field": "Communication Design",
          "start": "2018-08",
          "end": "2019-05"
        }
      ],
      "skills": [
        "Graphic Design",
        "Branding",
        "Social Media Design",
        "Illustration"
      ],
      "certificates": [],
      "languages": [],
      "awards": []
    }
  },
  "ai-automation": {
    "reviews": {
      "score": 4.9,
      "total": 20,
      "dimensions": {
        "responseSpeed": 4.9,
        "serviceQuality": 4.9,
        "skill": 5,
        "value": 4.8
      },
      "summary": [
        "Quick response times and clear communication throughout projects",
        "High-quality deliverables results",
        "Flexible to manage"
      ],
      "items": [
        {
          "id": "r1",
          "score": 5,
          "text": "Great results",
          "images": [
            "post-marketing.jpg"
          ],
          "author": {
            "name": "Chutima K.",
            "avatar": "r1.jpg"
          },
          "serviceId": "ai-automation-setup",
          "date": "2026-09-04"
        },
        {
          "id": "r2",
          "score": 4.5,
          "text": "Working with them on AI projects was amazing. Quick response and good qualities.",
          "images": [],
          "author": {
            "name": "Nattapong S.",
            "avatar": "r2.jpg"
          },
          "serviceId": "custom-ai-chatbot",
          "date": "2026-08-21"
        },
        {
          "id": "r3",
          "score": 5,
          "text": "A powerful AI solution that can solve our problems efficiently.",
          "images": [
            "post-spark.jpg"
          ],
          "author": {
            "name": "Sirilak M.",
            "avatar": "r3.jpg"
          },
          "serviceId": "ai-automation-setup",
          "date": "2026-08-02"
        }
      ]
    },
    "about": {
      "experience": [
        {
          "id": "agicafet",
          "logo": "logo-agicafet.jpg",
          "role": "Chief Executive Officer & Chief AI Officer",
          "company": "AGICAFET CO., LTD.",
          "start": "2024-03",
          "end": null
        },
        {
          "id": "tu-lab",
          "logo": "logo-thammasat-cs.jpg",
          "role": "Co-Founding Partner, AI HPC Platform Engineering Lab",
          "company": "Department of Computer Science, Thammasat University",
          "start": "2024-01",
          "end": null
        },
        {
          "id": "chula",
          "logo": "logo-chula.jpg",
          "role": "Guest Lecturer",
          "company": "Chulalongkorn University",
          "start": "2024-04",
          "end": "2024-12"
        },
        {
          "id": "deeplearning",
          "logo": "logo-deeplearning.jpg",
          "role": "Ambassador",
          "company": "DeepLearning.AI",
          "start": "2024-05",
          "end": null
        },
        {
          "id": "ai-alliance",
          "logo": "logo-ai-alliance.jpg",
          "role": "Ambassador",
          "company": "The AI Alliance",
          "start": "2023-08",
          "end": null
        },
        {
          "id": "beryll",
          "logo": "logo-beryll.jpg",
          "role": "AI Technology Advisor",
          "company": "Beryll",
          "start": "2023-11",
          "end": "2024-01"
        },
        {
          "id": "intefion",
          "logo": "logo-intefion.jpg",
          "role": "Senior AI Engineer",
          "company": "Intefion",
          "start": "2023-05",
          "end": "2023-11"
        },
        {
          "id": "axons",
          "logo": "logo-axons.jpg",
          "role": "AI Engineer",
          "company": "AXONS",
          "start": "2022-08",
          "end": "2023-05"
        },
        {
          "id": "kmitl",
          "logo": "logo-kmitl.jpg",
          "role": "Researcher",
          "company": "Faculty of Information Technology, King Mongkut's Institute of Technology Ladkrabang",
          "start": "2022-05",
          "end": "2024-12"
        },
        {
          "id": "phuetnoi",
          "logo": "logo-phuetnoi.jpg",
          "role": "Founder and Engineer",
          "company": "Phuetnoi",
          "start": "2024-04",
          "end": "2024-07"
        },
        {
          "id": "tokyo-tech",
          "logo": "logo-tokyo-tech.jpg",
          "role": "Young Scientist and Engineering Advanced Study",
          "company": "Tokyo Institute of Technology",
          "start": "2023-09",
          "end": "2023-10"
        },
        {
          "id": "baksters",
          "logo": "logo-baksters.jpg",
          "role": "AI Software Engineer",
          "company": "Baksters",
          "start": "2022-10",
          "end": "2023-01"
        }
      ],
      "education": [
        {
          "id": "kmitl",
          "logo": "logo-kmitl.jpg",
          "school": "School of Information Technology, King Mongkut's Institute of Technology Ladkrabang",
          "degree": "Master of Science - MS",
          "field": "Artificial Intelligence",
          "start": "2018-08",
          "end": "2024-05"
        },
        {
          "id": "mahidol",
          "logo": "logo-mahidol.jpg",
          "school": "Mahidol University",
          "degree": "Bachelor of Science",
          "field": "Radiologic Technology and Imaging Science",
          "start": "2013-08",
          "end": "2018-05"
        }
      ],
      "skills": [
        "Agentic",
        "Discord",
        "Community Engagement",
        "Artificial Intelligence (AI)"
      ],
      "certificates": [
        {
          "id": "nvidia-isaac",
          "logo": "logo-nvidia.jpg",
          "title": "NVIDIA Isaac for Accelerated Robotics",
          "issued": "2025-01",
          "issuer": "NVIDIA"
        },
        {
          "id": "google-ai",
          "logo": "logo-google.jpg",
          "title": "Google AI Professional Certificate",
          "issued": "2025-02",
          "issuer": "Google"
        }
      ],
      "languages": [
        {
          "id": "th",
          "name": "Thai",
          "level": "Native or bilingual proficiency"
        },
        {
          "id": "en",
          "name": "English",
          "level": "Professional working proficiency"
        }
      ],
      "awards": []
    }
  },
  "web-developer": {
    "reviews": {
      "score": 4.8,
      "total": 30,
      "dimensions": {
        "responseSpeed": 4.8,
        "serviceQuality": 4.8,
        "skill": 4.9,
        "value": 4.7
      },
      "summary": [
        "BigzWeb built a super clean, fast, and fully responsive website that exceeded our requirements.",
        "Communication was smooth, clear, and development milestones were met ahead of schedule.",
        "Exceptional technical execution, code quality, and post-launch support."
      ],
      "items": [
        {
          "id": "r1",
          "score": 5,
          "text": "Great problem-solving skills; transformed complex technical needs into a seamless web platform.",
          "images": [
            "post-speed-addict.jpg"
          ],
          "author": {
            "name": "Thanawat R.",
            "avatar": "r8.jpg"
          },
          "serviceId": "full-site",
          "date": "2026-09-04"
        },
        {
          "id": "r2",
          "score": 4.5,
          "text": "Outstanding optimization for SEO, mobile responsiveness, and page loading speed.",
          "images": [
            "post-haus-clinic.jpg"
          ],
          "author": {
            "name": "Patcharapa W.",
            "avatar": "r9.jpg"
          },
          "serviceId": "one-page",
          "date": "2026-08-21"
        }
      ]
    },
    "about": {
      "experience": [
        {
          "id": "bigzweb",
          "logo": "logo-bigzweb.png",
          "role": "Founder",
          "company": "BIGZWEB",
          "start": "2010-01",
          "end": null
        }
      ],
      "education": [
        {
          "id": "buu",
          "school": "Burapha University",
          "degree": "Engineering"
        }
      ],
      "skills": [
        "Web Development (HTML/CSS/JS/React)",
        "Full-Stack & API Integration",
        "E-Commerce & CMS Platforms",
        "Performance & SEO Optimization"
      ],
      "certificates": [],
      "languages": [],
      "awards": []
    }
  }
};
